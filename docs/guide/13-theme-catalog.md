# Theme catalog

`Facet.themes.neutralPackage()` returns the built-in neutral theme package. The
maintained game-owned theme packages are in `examples/themes`. Each module
exposes its theme package builder. The gallery applies theme packages through a
native StyleSheet and StyleLink.

| Theme package family | Purpose |
|---|---|
| Facet Neutral | Baseline semantic colors, control sizes and typography. Two palettes: `Dark` (the default) and `Light`. |
| Classic Desktop / Compact Pointer | Dense presentation for tools. |
| Glossy Mobile / Glossy Touch | Rounded, prominent touch controls. |
| Fantasy Parchment / Fantasy Ornate | Paper, framed surfaces and illustrated chrome. |
| Pixel Quest | Pixel artwork and deliberate resampling. |
| Sci-fi HUD | High-contrast instrument styling. |
| Custom-control, layered and ornate-gauge fixtures | Focused extension and skin tests. |

No shipped theme package declares the optional roles and metrics
(`selection`, `onSelection`, `scrim`, `inverseSurface`, `onInverse`,
`dimDisabledPlates`, `strongHairlineOpacity`, `controlSizes.xsmall`,
`targetSizes.pointer` or `strokes.utility`), so each one paints as before.
[Custom themes](09-custom-themes.md) tells what each one changes.

A package derived from Facet Neutral gets only its `Dark` palette. To offer a
light variant, declare it in the package, as Classic Desktop declares Day and
Night.

A theme package changes the appearance. It does not select a different
rendering architecture or device mode. The same controls, native layouts and
Compose owners stay in use.

```luau
local module = require(themeModule)
local package, report = module.build(Facet.themes)
assert(package, "Theme did not build")
local packageCell = Compose.cell(package)
local UI = Facet.controls(runtime, { theme = packageCell })
```

Before you use a module, check the actual return contract of its builder. Apply
the theme package as [custom themes](09-custom-themes.md) shows. Examine the
art loading and the semantic states in the real experience. The theme package
source and offline validation do not prove that the live assets are available.
