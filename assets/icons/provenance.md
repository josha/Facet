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

To add a glyph:

1. Draw it in the generator on the 128-pixel grid with the shared stroke,
   dot, ring and box helpers. Check it at 16, 20 and 24 pixels.
2. Run `lute run tools/facet art icons`.
3. Add its name to `standard_icons.ART` in `src/ui/icons.luau` with an empty
   `contentId`, and add its use to `ICON_USES` in
   `tools/facet/lib/docs_props.luau`.
4. Run `lute run tools/facet check docs-nodes --write`.
5. Run `lute run tools/facet icons upload` with `ROBLOX_API_KEY`. The command
   writes the content id into the manifest and the registry. A glyph without a
   content id shows no image.

A theme package's icons take precedence over standard icons. A package can
set `identity.standardIcons = false` and provide its own complete icon set.
See `src/ui/icons.luau` and `src/themes/package.luau` for resolution.

The silhouettes use near-white ink on transparency. `ImageColor3` multiplies
that ink by the theme color. Keep text separate from icons and check contrast
against the actual control surface. Standard sound icons use Roblox's bundled
speaker, volume, and mute artwork where declared by the icon registry.
