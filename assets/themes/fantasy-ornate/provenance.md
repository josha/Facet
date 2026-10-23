# Fantasy ornate artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../../LICENSE). Its source is
[`fantasy_ornate.luau`](../../../tools/facet/art/fantasy_ornate.luau).
It contains no external imagery.

The panel arrow uses only the panel's outer trim. The generator bends that
trim into an upward point and blends a short overlap into the frame.
The runtime rotates the complete arrow and join onto the selected edge.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art fantasy-ornate
lute run tools/facet art fantasy-ornate --check
```

The [upload manifest](upload-manifest.json) records asset IDs, image sizes,
and slice geometry. Use it as the asset reference. The generator defines the
shapes, palette, and deterministic generation inputs.

## Rendering constraints

Use gold frames, velvet surfaces, and jewel accents. Keep ornaments in fixed corners and edge bands uniform along the stretch axis. Keep bar fills uniform along the fill axis. Tile repeating rails and velvet textures; do not nine-slice them. Keep content insets equal across state variants. Near-white icon silhouettes receive their color from the theme. Do not bake text into plates.
