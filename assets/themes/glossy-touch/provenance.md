# Glossy touch artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../../LICENSE). Its source is
[`glossy_touch.luau`](../../../tools/facet/art/glossy_touch.luau).
It contains no external imagery.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art glossy-touch
lute run tools/facet art glossy-touch --check
```

The [upload manifest](upload-manifest.json) records asset IDs, image sizes,
and slice geometry. Use it as the asset reference. The generator defines the
shapes, palette, and deterministic generation inputs.

## Rendering constraints

Use gel surfaces with a vertical value change, sheen, and rim. Keep bar fills uniform along the fill axis. Tile the stripe texture; do not nine-slice it. Keep content insets equal across state variants. Render knobs as whole images and let the control own their geometry. Match foreground contrast to the visible plate color.
