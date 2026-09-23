# Theme catalog

The built-in neutral package is returned by `Facet.themes.neutralPackage()`. Maintained game-owned packages live in `examples/themes`; each module exposes its package builder. The gallery applies packages through a native StyleSheet and StyleLink.

| Package family | Purpose |
|---|---|
| Facet Neutral | Baseline semantic colors, control sizes and typography. |
| Classic Desktop / Compact Pointer | Dense tool-oriented presentation. |
| Glossy Mobile / Glossy Touch | Rounded, prominent touch controls. |
| Fantasy Parchment / Fantasy Ornate | Paper, framed surfaces and illustrated chrome. |
| Pixel Quest | Pixel artwork and deliberate resampling. |
| Sci-fi HUD | High-contrast instrument styling. |
| Custom-control, layered and ornate-gauge fixtures | Focused extension and skin tests. |

A package changes appearance; it does not choose a separate rendering architecture or device mode. The same controls, native layouts and Compose owners remain in use.

```luau
local module = require(themeModule)
local package, report = module.build(Facet.themes)
assert(package, "Theme did not build")
local packageCell = Compose.cell(package)
local UI = Facet.controls(runtime, { theme = packageCell })
```

Check the builder's actual return contract when using a particular module. Apply the package as shown in [custom themes](09-custom-themes.md). Inspect loading art and semantic states in the real experience; package source and offline validation alone do not prove live asset availability.
