# 13 — The theme catalog

> **In plain words.** Facet arrives wearing one look. That look is deliberately
> quiet. Eight other looks exist. Each is a single file you can install in one
> call, and none of them lives inside the library. This chapter is the shelf: what
> each package looks like, what it does to your layout, how to put one in, and
> what it costs.

Chapters [09](09-custom-themes.md) and [10](10-rich-skinning.md) teach you to
*write* a theme. This one is for the moment before that, when the honest question
is whether somebody has already written the one you want.

---

## 13.1 What is in the box, and what is not

**Studio Neutral is built in.** It is the library's own theme — a flat, legible,
Roblox-shaped look with a 44 px hit floor, a 4/8/16/24/40 spacing ladder and
16 px body text. Every control in Facet is drawn and measured against it. Every
example starts from it. You never install it: a screen with no theme package
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

`build/themes/manifest.json` is the machine-readable form of the table below. For
each package, it records the identity stamp, the themes inside it, its theme
classes, its declared asset count and its size on disk. All of it comes from the
*compiled* package, not from the source.

## 13.2 Installing one

There are two routes in. Both end at the same call.

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
    theme = "Grand Hall",     -- optional; defaults to the package's own default
})
```

**Present your first screen before you install.** The controller links its sheet
at the target's root. A target has no root until it has drawn one, so an install
that runs before the first `present` has nothing to link to. On the real client
target, this shows as an error naming the missing root. Headless, there are no
`StyleSheet`s to link anyway, so it quietly takes the fallback paint arm instead —
the more confusing behavior of the two. Stand the surface up, then install.

That is the whole installation. `install` is per-target and all-or-nothing. A
theme change is a re-solve, not a rebuild. `controller.swap("Crypt")` moves to
another theme of the same package in one atomic commit. All of this works exactly
as [chapter 09 §9.8](09-custom-themes.md) describes, because it is the same call.

Every package is verified against this path before it ships. `tools/check_theme_artifacts.py`
installs each built artifact in a tree that contains a copy of the library **and
nothing else** — no `examples/`, no gallery. It compiles the artifact, runs the
coverage gate, installs it, and mounts a real control under it. It repeats this
once per declared theme and once at a ten-foot display class.

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
second, native sheet — the screen target builds it only when it is running the
built-in style. A game package carries no light variant to derive one from. So a
package that wants two lights declares two themes, the way Classic Desktop
declares Day and Night.

**Glossy Touch and Compact Pointer are a pair.** Hand them to `selectBy` together.
One game then wears the thumb-sized skin on a phone and the dense one on a
desktop, and switches when a player docks a mouse:

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
version is better than any screenshot. **The showcase's theme picker demonstrates
every package in this catalog**, one tap apart, on whatever device you run it on.
See [§13.6](#136-the-showcase-is-this-catalog-running).

### Classic Desktop — `ClassicDesktop.rbxm`

*One screenshot:* a settings pane that looks like a workstation utility. Square
edges, hairline separators, rows packed close enough that a dozen fit where six
would in the default. No gradients anywhere.

- **Metrics.** Half the neutral spacing ladder (2/4/8/12/20 against 4/8/16/24/40)
  and 22/26/32 px control heights against 36/44/56. Body text is 13 px
  BuilderSans. The 44 px accessibility floor still applies to the *hit* rect —
  the presenter expands it. So a dense desktop theme is tight to look at, and
  still reachable with a finger.
- **Chrome.** Every slot is native paint: zero decoration instances, no images.
- **Two themes, one geometry.** "Day" and "Night" differ in colour and in nothing
  else, so swapping between them repaints without re-solving a single dimension.
- **Take it when** your interface is a tool — a build menu, an admin panel, a
  spreadsheet-shaped screen — and the player is at a keyboard.

### Glossy Mobile — `GlossyMobile.rbxm`

*One screenshot:* a phone-shaped card stack with generously rounded corners, big
soft buttons and a lot of air; nothing is sharp and nothing is small.

- **Metrics.** The roomiest package here. It sets an 18 px `space.m`, 52 px
  regular rows and a 24 px panel radius. The hit floor rises to 48 px, above the
  accessibility minimum on purpose. Body text is 17 px Nunito.
- **Chrome.** Native paint with gradients; no images at all.
- **Take it when** the interface is phone-first and you want the default look to
  feel modern and friendly without shipping a single asset.

### Sci-Fi HUD — `ScifiHud.rbxm`

*One screenshot:* a cold blue instrument panel — every corner square, every edge a
2 px rule, headings in a wide technical font, directional washes across the panels.

- **Metrics.** Every radius is `0`. Strokes double to 2 px. The type ladder runs
  on Michroma, a font nothing like Builder Sans — that is the point. A package
  that moves the font family by a hair proves nothing about measurement.
- **Chrome.** Native paint plus a focus *glow*; no images.
- **Take it when** the fiction is a cockpit, a terminal or a station, and you want
  the geometry to say so before the colours do.

### Fantasy Parchment — `FantasyParchment.rbxm`

*One screenshot:* a quest log on aged paper — a nine-sliced parchment panel with a
torn edge, ink-brown calligraphy, a wax-seal slider thumb.

- **Metrics.** Close to neutral in size: 46 px rows, 16 px spacing step. It uses a
  16 px Fondamento body and a 1.35 line height, because a calligraphic font needs
  more air between lines than a UI sans.
- **Chrome.** Six images across panel, control, field, badge and the slider pair;
  the selection slot stays native.
- **Two themes.** "Daylight" and "Candlelight" — the same paper by different light.
- **Take it when** you want an art-backed skin without an art budget: six images
  is the smallest asset-backed package in the catalog.

### Fantasy Ornate — `FantasyOrnate.rbxm`

*One screenshot:* a torch-lit great hall. The panel is built from a velvet tile,
a gilded frame, tiled edge rails and corner ornaments, with a plaque across the
top. Every button is a painted plate that changes art when you press it.

- **Metrics.** The same ladder as Fantasy Parchment (they are siblings), plus
  namespaced metrics for the rung-3 gauge control.
- **Chrome.** The heaviest package here, and deliberately so. It uses 33 images
  and six-layer panels (tile → fill → frame → edges → corners → plaque). It adds
  per-state control art, image value bars with two end caps, and a focus **glow**
  rather than a ring.
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

- **Metrics.** 44 px rows at *both* the compact and the regular size class. A
  touch skin never draws a small row. 18 px spacing step, 17 px Nunito.
- **Chrome.** 14 images across control, field, selection, toggle, stepper and the
  bar pair. The bar track is layered: its stripe tile rides the **track**, over a
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

There are three costs. Only one of them is the file.

**1. The artifact.** 4.2 KB to 14.7 KB of Luau — the numbers in the table above,
read off the built `.rbxm`. This is the cheapest part and rarely the interesting
one.

**2. The art, which is an upload, not a download.** The five asset-backed packages
reference Roblox content IDs. Those IDs are *this repository's* uploads. The
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
native paint Facet already emits. Classic Desktop, Glossy Mobile and Sci-Fi HUD
declare `kind = "native"` for every slot, and create zero decoration instances. An
asset-backed package creates real `ImageLabel`s per decorated node. A layered one
creates several — Fantasy Ornate's panel is six layers deep. This cost shows up
in frame time, not file size. It is measured, not estimated.

> **Pending — the memory table.** The per-package instance and heap figures are
> not measured yet, and neither are the install and swap timings. Until they are,
> this section states the shape of the cost and deliberately quotes no number for
> it: an estimate here would be an unsupported claim.
>
> The instrument already exists. The screen target publishes `adapter.chromeCensus()`,
> which counts the decoration instances a package actually created. The
> performance lab compares a flat package against Fantasy Ornate over an
> identical workload, timing install, steady scroll and teardown apart
> ([chapter 12](12-performance-lab.md)).

## 13.6 The showcase is this catalog, running

The showcase place ships **every package in this catalog**, and its theme picker
is the catalog, live. Open it, tap a package, tap a theme. The whole interface
re-solves in place, without losing focus, scroll position or anything you had
typed. It is the fastest way to decide which one you want. It is also the only
way to see a package on your own device, at your own accessibility settings.

The picker deliberately hides the modules in `examples/themes/` that are **not**
packages a player may install: the refusal fixtures, and the two rung-3 control
examples. The refusal fixtures exist because some of their variants are broken
on purpose. Those are the test corpus. `tools/lune/theme_packages.luau` records
which is which, and why. `tools/build_themes.sh` builds artifacts for the eight
shippable packages only.

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
