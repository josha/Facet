# Fantasy parchment artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../../LICENSE). Its source is
[`fantasy_parchment.luau`](../../../tools/facet/art/fantasy_parchment.luau).
It contains no external imagery.

The panel arrow uses the panel's centre edge strip. The generator bends its
bands into an upward point and blends the lower overlap into the panel fill.
The runtime rotates the complete arrow and join onto the selected edge.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art fantasy-parchment
lute run tools/facet art fantasy-parchment --check
```

The [upload manifest](upload-manifest.json) records asset IDs, image sizes,
and slice geometry. Use it as the asset reference. The generator defines the
shapes, palette, and deterministic generation inputs.

## Rendering constraints

The art uses procedural paper noise, stains, deckled edges, and ink. Keep the panel and control borders fixed with the manifest slice geometry. Use theme tint for control states. Keep text separate from the plate artwork.
