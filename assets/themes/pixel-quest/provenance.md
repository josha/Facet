# Pixel quest artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../../LICENSE). Its source is
[`pixel_quest.luau`](../../../tools/facet/art/pixel_quest.luau).
It contains no external imagery.

The panel arrow uses only the panel's outer trim. The generator bends that
trim into an upward point and blends a short overlap into the frame.
The runtime rotates the complete arrow and join onto the selected edge.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art pixel-quest
lute run tools/facet art pixel-quest --check
```

The [upload manifest](upload-manifest.json) records asset IDs, image sizes,
and slice geometry. Use it as the asset reference. The generator defines the
shapes, palette, and deterministic generation inputs.

## Rendering constraints

The art uses a four-pixel design grid. Use Pixelated resampling, integer SliceScale, and metrics aligned to the grid. Do not smooth the pixels. Selected plates must preserve content insets. Keep bar fills uniform along the fill axis and end ornaments separate from the clipped fill. Use icon sizes that preserve the grid. A package with identity.standardIcons = false must provide its complete required icon set.
