# Compact pointer artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../../LICENSE). Its source is
[`compact_pointer.luau`](../../../tools/facet/art/compact_pointer.luau).
It contains no external imagery.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art compact-pointer
lute run tools/facet art compact-pointer --check
```

The [upload manifest](upload-manifest.json) records asset IDs, image sizes,
and slice geometry. Use it as the asset reference. The generator defines the
shapes, palette, and deterministic generation inputs.

## Rendering constraints

Use compact controls with a light backing and a one-pixel edge. Keep the same content insets across default, hover, and pressed assets. Keep bar fills uniform along the fill axis. Use the manifest slice geometry at SliceScale 1; shrinking below the fixed borders distorts the art.
