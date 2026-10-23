# Standard icon artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../LICENSE). Its source is
[`icons.luau`](../../tools/facet/art/icons.luau). It contains no external imagery.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art icons
lute run tools/facet art icons --check
```

The [upload manifest](upload-manifest.json) records the uploaded assets.
The generator defines the shapes and rasterization. Inspect the
[contact sheet](source/preview/contact-sheet.png) at the intended display sizes.

A theme package's icons take precedence over standard icons. A package can
set `identity.standardIcons = false` and provide its own complete icon set.
See `src/ui/icons.luau` and `src/themes/package.luau` for resolution.

The silhouettes use near-white ink on transparency. `ImageColor3` multiplies
that ink by the theme color. Keep text separate from icons and check contrast
against the actual control surface. Standard sound icons use Roblox's bundled
speaker, volume, and mute artwork where declared by the icon registry.
