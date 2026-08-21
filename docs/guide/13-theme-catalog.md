# 13 — The theme catalog

> **In plain words.** Facet arrives wearing one look, and it is deliberately a
> quiet one. Eight other looks exist, each a single file you can install in one
> call, and none of them is inside the library. This chapter is the shelf: what
> each package looks like, what it does to your layout, how to put one in, and
> what it costs.

Chapters [09](09-custom-themes.md) and [10](10-rich-skinning.md) teach you to
*write* a theme. This one is for the moment before that, when the honest question
is whether somebody has already written the one you want.

---

## 13.1 What is in the box, and what is not

**Studio Neutral is built in.** It is the library's own theme — a flat, legible,
Roblox-shaped look with a 44 px hit floor, a 4/8/16/24/40 spacing ladder and
16 px body text. Every control in Facet is drawn and measured against it, every
example starts from it, and you never install it: a screen with no theme package
at all is already wearing it. If you never read another word of this chapter, you
still have a complete, accessible interface.

**Everything else is a package you pick.** `build/Facet.rbxm` contains `src/` and
nothing else — the engine plus Studio Neutral. The eight packages below each build
to their own artifact under `build/themes/`, so taking a skin never means taking
the gallery, the fixtures, or the eight other skins. `tools/check_library_purity.py`
is what keeps that true: the shipped library names no reference package anywhere in
its code, and the model carries exactly one package identity, `studio-neutral`.

Build the artifacts with:

```bash
tools/build_themes.sh     # -> build/themes/*.rbxm + build/themes/manifest.json
```

`build/themes/manifest.json` is the machine-readable form of the table below: the
identity stamp, the themes inside each package, its theme classes, its declared
asset count and its size on disk, all read from the *compiled* package rather than
scraped out of the source.

## 13.2 Installing one

Two routes in, and they end at the same call.

**With Rojo**, the package is just a module in your tree; require it wherever you
keep game modules.

**Without Rojo** ([chapter 08](08-without-rojo.md)), drag
`build/themes/<Name>.rbxm` into `ReplicatedStorage` beside `Facet`. Each artifact
is one `ModuleScript` named for the package, so `FantasyOrnate.rbxm` becomes
`ReplicatedStorage.FantasyOrnate`.

Then, on the client, at the point where your UI is set up:

```lua
local Facet = require(ReplicatedStorage.Facet)
local theme_controller = require(ReplicatedStorage.Facet.client.theme_controller)

-- the package module compiles itself through the PUBLIC theme surface
local package = require(ReplicatedStorage.FantasyOrnate).build(Facet.themes)

local controller = theme_controller.install(adapter, package, {
    env = env,                -- REQUIRED: the metric snapshot rides it
    rootGui = rootHandle.gui, -- the target's root ScreenGui
    theme = "Grand Hall",     -- optional; defaults to the package's own default
})
```

That is the whole installation. `install` is per-target and all-or-nothing, a
theme change is a re-solve rather than a rebuild, and `controller.swap("Crypt")`
moves to another theme of the same package in one atomic commit — all of it
exactly as [chapter 09 §9.8](09-custom-themes.md) describes, because it is the
same call.

Every package is verified against this path before it ships:
`tools/check_theme_artifacts.py` installs each built artifact in a tree that
contains a copy of the library **and nothing else** — no `examples/`, no gallery —
compiles it, runs the coverage gate, installs it and mounts a real control under
it, once per declared theme and once at a ten-foot display class.

## 13.3 The catalog at a glance

Sizes are the built `.rbxm`; "art" is the uploaded decoration the package
references (see [§13.5](#135-what-a-package-actually-costs)).

| Package | Artifact | Themes | Character | Art | Size |
|---|---|---|---|---|---|
| *(built in)* **Studio Neutral** | — | Dark, Light\* | the flat default: 44 px rows, 16 px body, soft 8/12 px corners | none | — |
| **Classic Desktop** | `ClassicDesktop.rbxm` | Day, Night | dense workstation: 26 px rows, 13 px body, square corners, hairline strokes | none | 4.2 KB |
| **Glossy Mobile** | `GlossyMobile.rbxm` | Daylight | roomy and rounded: 52 px rows, 18 px spacing step, 24 px panel radius, 48 px hit floor | none | 4.8 KB |
| **Sci-Fi HUD** | `ScifiHud.rbxm` | Nightwatch | angular and cold: zero radii everywhere, 2 px strokes, Michroma display face | none | 5.4 KB |
| **Fantasy Parchment** | `FantasyParchment.rbxm` | Daylight, Candlelight | nine-slice parchment and ink, Fondamento calligraphy, 46 px rows | 6 images | 8.7 KB |
| **Fantasy Ornate** | `FantasyOrnate.rbxm` | Grand Hall, Crypt | the fully painted one: six-layer panels, per-state art, image bars, a focus *glow* | 33 images | 14.7 KB |
| **Pixel Quest** | `PixelQuest.rbxm` | Quest | pixel-art mode: every metric snapped to a 4 px grid, 4 px strokes, nearest-neighbour scaling | 20 images | 10.1 KB |
| **Glossy Touch** | `GlossyTouch.rbxm` | Sky | the thumb-first skin: 44 px rows at every size class, 10/14 px radii, sliced plates | 14 images | 9.3 KB |
| **Compact Pointer** | `CompactPointer.rbxm` | Aqua | the mouse-first partner to Glossy Touch: 24 px rows, 10 px spacing step, 13 px body | 12 images | 7.0 KB |

\* Studio Neutral's *package* declares one theme, `Dark`. The Light variant is a
second native sheet the screen target builds only when it is running the built-in
style — a game package carries no light variant to derive one from, so a package
that wants two lights declares two themes, the way Classic Desktop declares Day
and Night.

**Glossy Touch and Compact Pointer are a pair.** They exist to be handed to
`selectBy` together, so one game wears the thumb-sized skin on a phone and the
dense one on a desktop, and switches when a player docks a mouse:

```lua
theme_controller.install(adapter, glossyTouch, {
    env = env,
    core = core,                          -- selectBy needs a scope for its subscription
    selectBy = { pointer = compactPointer },
})
```

Nothing new is detected: `selectBy`'s vocabulary is exactly the interaction
classes the environment already publishes ([chapter 10](10-rich-skinning.md)).

## 13.4 The packages

Each entry describes what a single screenshot of the package shows. The live
version is better than any screenshot: **the showcase's theme picker demonstrates
every package in this catalog**, one tap apart, on whatever device you run it on —
see [§13.6](#136-the-showcase-is-this-catalog-running).

### Classic Desktop — `ClassicDesktop.rbxm`

*One screenshot:* a settings pane that looks like a workstation utility — square
edges, hairline separators, rows packed close enough that a dozen fit where six
would in the default, no gradients anywhere.

- **Metrics.** Half the neutral spacing ladder (2/4/8/12/20 against 4/8/16/24/40)
  and 22/26/32 px control heights against 36/44/56. Body text is 13 px
  BuilderSans. The 44 px accessibility floor still applies to the *hit* rect —
  the presenter expands it — so a dense desktop theme is tight to look at and
  still reachable with a finger.
- **Chrome.** Every slot is native paint: zero decoration instances, no images.
- **Two themes, one geometry.** "Day" and "Night" differ in colour and in nothing
  else, so swapping between them repaints without re-solving a single dimension.
- **Take it when** your interface is a tool — a build menu, an admin panel, a
  spreadsheet-shaped screen — and the player is at a keyboard.

### Glossy Mobile — `GlossyMobile.rbxm`

*One screenshot:* a phone-shaped card stack with generously rounded corners, big
soft buttons and a lot of air; nothing is sharp and nothing is small.

- **Metrics.** The roomiest package here: an 18 px `space.m`, 52 px regular rows,
  a 24 px panel radius and a hit floor raised to 48 px — above the accessibility
  minimum on purpose. Body text is 17 px Nunito.
- **Chrome.** Native paint with gradients; no images at all.
- **Take it when** the interface is phone-first and you want the default look to
  feel modern and friendly without shipping a single asset.

### Sci-Fi HUD — `ScifiHud.rbxm`

*One screenshot:* a cold blue instrument panel — every corner square, every edge a
2 px rule, headings in a wide technical face, directional washes across the panels.

- **Metrics.** Every radius is `0`, strokes double to 2 px, and the type ladder
  runs on Michroma, a face nothing like Builder Sans — which is the point: a
  package that moves the family by a hair proves nothing about measurement.
- **Chrome.** Native paint plus a focus *glow*; no images.
- **Take it when** the fiction is a cockpit, a terminal or a station, and you want
  the geometry to say so before the colours do.

### Fantasy Parchment — `FantasyParchment.rbxm`

*One screenshot:* a quest log on aged paper — a nine-sliced parchment panel with a
torn edge, ink-brown calligraphy, a wax-seal slider thumb.

- **Metrics.** Close to neutral in size (46 px rows, 16 px spacing step) with a
  16 px Fondamento body and a 1.35 line height, because a calligraphic face needs
  more air between lines than a UI sans.
- **Chrome.** Six images across panel, control, field, badge and the slider pair;
  the selection slot stays native.
- **Two themes.** "Daylight" and "Candlelight" — the same paper by different light.
- **Take it when** you want an art-backed skin without an art budget: six images
  is the smallest asset-backed package in the catalog.

### Fantasy Ornate — `FantasyOrnate.rbxm`

*One screenshot:* a torch-lit great hall — a panel built from a velvet tile, a
gilded frame, tiled edge rails and corner ornaments, with a plaque across the top
and every button a painted plate that changes art when you press it.

- **Metrics.** The same ladder as Fantasy Parchment (they are siblings), plus
  namespaced metrics for the rung-3 gauge control.
- **Chrome.** The heaviest package here and deliberately so: 33 images, six-layer
  panels (tile → fill → frame → edges → corners → plaque), per-state control art,
  image value bars with two end caps, and a focus **glow** rather than a ring.
- **Two themes, one art set.** "Grand Hall" is torch-lit oak and gold; "Crypt" is
  the same architecture underground, colder and blue-lit. Each names its own
  focus glow, because a halo has to out-value the surface it sits on.
- **Take it when** the art *is* the interface. Read its cost line honestly first.

### Pixel Quest — `PixelQuest.rbxm`

*One screenshot:* a 16-bit inventory screen — chunky 4 px borders, hard-edged
plates, heart-shaped bar caps, and not one soft pixel anywhere.

- **Metrics.** The only package with a **pixel unit**: every resolved metric snaps
  up to a multiple of 4, so nothing ever lands on a half-pixel. Strokes are 4 px.
  This snapping applies to derived metrics too — at a ten-foot display class its
  hit floor resolves to 68 px rather than 66, because the package's own grid wins.
- **Chrome.** 20 images, drawn with nearest-neighbour scaling so enlargement stays
  crisp instead of turning to mush.
- **Take it when** the game is pixel art. Mixing a pixel skin with smooth art
  reads as a mistake, not a contrast.

### Glossy Touch — `GlossyTouch.rbxm`

*One screenshot:* a bright, sky-blue phone HUD — every row a comfortable thumb
target, sliced plates with a soft sheen, a striped progress bar.

- **Metrics.** 44 px rows at *both* the compact and the regular size class: a
  touch skin refuses to draw a small row at all. 18 px spacing step, 17 px Nunito.
- **Chrome.** 14 images across control, field, selection, toggle, stepper and the
  bar pair, with a layered bar track — its stripe tile rides the **track**, over a
  plain sliced fill.
- **Take it when** the game is played with thumbs. Pair it with Compact Pointer
  through `selectBy` and one install covers both.

### Compact Pointer — `CompactPointer.rbxm`

*One screenshot:* the same aqua interface as Glossy Touch, rebuilt for a mouse —
half the row height, tight gaps, small crisp plates, more content per screen.

- **Metrics.** 24 px regular rows, a 10 px spacing step and 13 px body text. The
  hit floor stays 44 px, so precision costs nothing in reachability.
- **Chrome.** 12 images, the same vocabulary as its partner at a smaller scale.
- **Take it when** you are shipping the pointer half of a `selectBy` pair, or the
  game is desktop-first but wants painted chrome.

## 13.5 What a package actually costs

Three costs, and only one of them is the file.

**1. The artifact.** 4.2 KB to 14.7 KB of Luau — the numbers in the table above,
read off the built `.rbxm`. This is the cheapest part and rarely the interesting
one.

**2. The art, which is an upload, not a download.** The five asset-backed packages
reference Roblox content IDs, and those IDs are *this repository's* uploads. The
source PNGs live in `assets/themes/<package-id>/` with a `provenance.md` recording
how they were generated and an `upload-manifest.json` recording every ID the
package uses. **Another project uploads the same PNGs under its own account and
substitutes its own IDs** — nothing in a package hardcodes an ID outside its
package data. On disk the art weighs:

| Package | Images | Source PNGs on disk |
|---|---|---|
| Fantasy Parchment | 6 | 140 KB |
| Compact Pointer | 12 | 140 KB |
| Glossy Touch | 14 | 240 KB |
| Pixel Quest | 20 | 176 KB |
| Fantasy Ornate | 33 | 440 KB |

**3. Runtime decoration instances.** A flat package costs nothing beyond the
native paint Facet already emits: Classic Desktop, Glossy Mobile and Sci-Fi HUD
declare `kind = "native"` for every slot and create zero decoration instances. An
asset-backed package creates real `ImageLabel`s per decorated node, and a layered
one creates several — Fantasy Ornate's panel is six layers deep. That is the cost
that shows up in a frame time rather than a file size, and it is measured rather
than estimated.

> **Pending — the memory table.** The per-package instance and heap figures belong
> in the release performance wave's measured table, alongside the install and swap
> timings. Until that wave lands, this section states the shape of the cost and
> deliberately quotes no number for it: an estimate here would be an unsupported
> claim, which is exactly what the distribution plan forbids. The instrument
> already exists — the screen target publishes `adapter.chromeCensus()`, which
> counts the decoration instances a package actually created, and the performance
> lab compares a flat package against Fantasy Ornate over an identical workload
> with install, steady scroll and teardown timed apart
> ([chapter 12](12-performance-lab.md)).

## 13.6 The showcase is this catalog, running

The showcase place ships **every package in this catalog** and its theme picker is
the catalog live: open it, tap a package, tap a theme, and the whole interface
re-solves in place without losing focus, scroll position or anything you had
typed. It is the fastest way to decide which one you want, and the only way to see
a package on your own device at your own accessibility settings.

The picker deliberately hides the modules in `examples/themes/` that are **not**
packages a player may install — the refusal fixtures, whose whole purpose is that
some of their variants are broken on purpose, and the two rung-3 control examples.
Those are the test corpus; `tools/lune/theme_packages.luau` records which is which
and why, and `tools/build_themes.sh` builds artifacts for the eight shippable
packages only.

## 13.7 None of these? Write one

- **[09 — Custom themes](09-custom-themes.md)** builds a package end to end from
  Studio Neutral: paint, fonts, metrics, nine-slice chrome, live editing in the
  Style Editor, validation and install.
- **[10 — Rich skinning](10-rich-skinning.md)** is the same road further: layered
  decoration, per-state art, image bars, semantic icons, pixel mode, `selectBy`,
  and a custom control that ships its own art.
- **[`docs/extending/new-theme.md`](../extending/new-theme.md)** is the
  contributor playbook, including what the package linter accepts and refuses.

Every package in this catalog is written against the public API and nothing else —
`themes.define` and `themes.neutralPackage()`, no internal require anywhere. That
is deliberate and it is checked: a reference package that needed an internal
import would be evidence the public surface is insufficient. Copy any of them from
`examples/themes/` and start editing.
