# THEME-UNBUNDLE — the artifacts, and what proves each one installs alone

## What was built

`tools/build_themes.sh` (a sibling of `tools/build_model.sh`, sharing its whole
shape — the rokit PATH pin, the throwaway project, one `rojo build`) emits one
`.rbxm` per shippable reference package plus a manifest compiled through
`themes.define`. Regenerate with `tools/build_themes.sh`; `build/` is gitignored,
so these numbers are the record.

Measured 2026-08-21, Facet 0.10.0, theme schema `facet-theme/1`:

| Module | Artifact | Package id | Version | Themes | Theme classes | Declared assets | Bytes |
|---|---|---|---|---|---|---|---|
| `classic_desktop` | `ClassicDesktop.rbxm` | `classic-desktop` | 1.0.0 | Day, Night | palette, metrics | 0 | 4,229 |
| `compact_pointer` | `CompactPointer.rbxm` | `compact-pointer` | 1.0.0 | Aqua | palette, metrics, font, assets | 12 | 6,962 |
| `fantasy_ornate` | `FantasyOrnate.rbxm` | `fantasy-ornate` | 1.0.0 | Grand Hall, Crypt | palette, metrics, font, assets | 33 | 14,664 |
| `fantasy_parchment` | `FantasyParchment.rbxm` | `fantasy-parchment` | 1.0.0 | Daylight, Candlelight | palette, metrics, font, assets | 6 | 8,653 |
| `glossy_mobile` | `GlossyMobile.rbxm` | `glossy-mobile` | 1.0.0 | Daylight | palette, metrics, font | 0 | 4,816 |
| `glossy_touch` | `GlossyTouch.rbxm` | `glossy-touch` | 1.0.0 | Sky | palette, metrics, font, assets | 14 | 9,315 |
| `pixel_quest` | `PixelQuest.rbxm` | `pixel-quest` | 1.0.0 | Quest | palette, metrics, assets | 20 | 10,107 |
| `scifi_hud` | `ScifiHud.rbxm` | `scifi-hud` | 1.0.0 | Nightwatch | palette, metrics, font | 0 | 5,373 |
Eight artifacts, 63,119 bytes total. Every one is a single `ModuleScript` named
for the artifact, with no children — asserted, because a package that grew
runtime data beside its module would otherwise ship half of itself in silence.

## What is NOT shippable, and why

`tools/lune/theme_packages.luau` holds the reasons in full; in short:

| Module | Why it is not a product |
|---|---|
| `fantasy_parchment_stub` | a REFUSAL fixture wearing a reference package's clothes — `buildBadAsset`, `buildBadFont` and `buildIncompatible` are broken on purpose. `testOnly = true`. The shipping skin of this name is `fantasy_parchment`. |
| `content_alias_test` | an A/B fixture: the same package compiled twice, once spelling every asset `content` and once `contentId`. Two identities, one skin, nothing to pick. |
| `layered_test` | the layer-vocabulary probe — every rung of the layer ladder in isolation, with deliberate failures the scenarios drive. |
| `custom_control` | not a theme package at all: the rung-3 conformance fixture for a namespaced CONTROL. No `id`, no `displayName`, no `build`. |
| `ornate_gauge` | the rung-3 worked example — a control with its own art. A game copies the file; it is not a package a player selects. |

The partition is TOTAL and `theme_packages.check()` enforces it: a module in
neither set fails, so "nobody decided yet" cannot read as "ship it". The five
exclusions each require a reason of real length, because an empty string would
satisfy a `~= nil` test and tell the next reader nothing.

## The self-containment proof

`python3 tools/check_theme_artifacts.py` — 8 artifacts, **137 checks**, green.

Per artifact it builds the XML twin through the SAME `build_themes.sh --one`
mapping, asserts the shape (one root ModuleScript, right name, a Source, no
children), asserts the code calls `require` NOWHERE, then extracts every Source
into an isolated tree that holds a copy of `src/`, the headless world and nothing
else — **no `examples/` anywhere above the artifacts** — and runs
`tools/lune/theme_artifact_probe.luau` there:

1. the extracted Source loads and `build(themes)` compiles it;
2. its identity stamp matches the manifest (id, version, schemaVersion) and its
   schema is this build's;
3. `themes.checkCoverage` accepts it as a compiled package AND is live — an
   undeclared `probe:dial` need is reported, so the empty-list pass is not vacuous;
4. `theme_controller.install` installs it on a bare adapter and a real
   `UI.Button` mounts at a drawable size, **once per declared theme** (12 installs
   across the eight packages);
5. the same package at a **ten-foot display class** (ADR-0039): the ladder moves
   `targetSizes.minimum`, `controlSizes.regular.height` and `space.m` by
   `themes.metricScale`, the artifact's `metrics.tenFoot` pin count matches the
   manifest, and the mounted button is taller at three metres than at a desk.

In-repo none of this is falsifiable: `examples/` is one directory above every
theme module, so a package that quietly required the gallery would compile, pass
the suite, and fail only for the first consumer who installed the artifact alone.

### The ten-foot rows, and the measurement that corrected the assertion

No shippable package declares `metrics.tenFoot` today (the manifest records
`tenFootOverrides: 0` for all eight), so every one of them rides the derived
ladder — which is what the probe asserts, per package, per metric.

The first run of that assertion FAILED on `pixel_quest`, twice: the ten-foot hit
floor resolved to 68 and the ladder puts it at 66. That was the assertion being
wrong, not the ladder. A pixel-mode package snaps every resolved metric UP to its
own unit (4 px here), so 66 lands on 68 and the package is being obeyed. The
assertion now reads `near * factor <= far <= near * factor + pixelUnit`, and
`pixelUnit` is a PUBLISHED field of the resolved snapshot — naming it as the
tolerance reads the framework's answer instead of re-deriving its rule.

### The negative controls

`python3 tools/check_theme_artifacts.py --selftest`, four plants, each in a
scratch copy (this repository's shared tree is never modified — other agents are
in it):

    theme_artifact_probe: 8 artifacts installed against a bare library, 137 checks OK
      selftest control: the unplanted tree passes
      [BITES] a package that reaches into examples/ (the gallery's theme picker)
          -> ClassicDesktop: the artifact's code calls require() at line ~19. A theme package is data handed the `themes` table by its caller; a require is a dependency the artifact cannot carry, and a consumer installing it alone would fail at that line
      [BITES] an artifact whose identity stamp drifted from the manifest
          -> probe: - ScifiHud: artifact version '9.9.9' != manifest '1.0.0'
      [BITES] an artifact that lost its package body
          -> probe: - PixelQuest: the artifact returns no theme package — a shippable module exposes build(themes) -> (package, report), and this one exposes table
      [BITES] a package whose metrics.tenFoot names a metric that does not exist
          -> probe: - ClassicDesktop/Day: install failed — /private/var/folders/3k/jlz721jd3vj3clf5mkvvqvyc0000gn/T/facet-theme-artifacts-r_1s3f4j/src/themes/snapshot:1400: themes.resolve: metrics.tenFoot['space.enormous'] names no metric in this package's snapshot (use a dotted path such as "space.m" or "targetSizes.minimum")
          -> probe: - ClassicDesktop/Night: install failed — /private/var/folders/3k/jlz721jd3vj3clf5mkvvqvyc0000gn/T/facet-theme-artifacts-r_1s3f4j/src/themes/snapshot:1400: themes.resolve: metrics.tenFoot['space.enormous'] names no metric in this package's snapshot (use a dotted path such as "space.m" or "targetSizes.minimum")

The third plant is the reason the probe was restructured. Its first run
stack-traced at `module.build(...)` and reported nothing about WHICH artifact had
been emptied — a probe that crashes on the defect it exists to find is a poor
instrument, so every per-package body now runs under `pcall` and an error becomes
a reported failure like any other.

The fourth is a `metrics.tenFoot` path naming no metric: a declaration that
compiles clean and only fails when the artifact is INSTALLED, which is exactly
the class an artifact-level check exists to catch.
