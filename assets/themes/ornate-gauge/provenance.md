# Ornate gauge artwork

This is original, repository-owned procedural artwork, licensed under the
repository [license](../../../LICENSE). Its source is
[`ornate_gauge.luau`](../../../tools/facet/art/ornate_gauge.luau).
It contains no external imagery.

Regenerate or check the committed art from the repository root:

```sh
lute run tools/facet art ornate-gauge
lute run tools/facet art ornate-gauge --check
```

The [upload manifest](upload-manifest.json) records asset IDs, image sizes,
and slice geometry. Use it as the asset reference. The generator defines the
shapes, palette, and deterministic generation inputs.

## Rendering constraints

These assets belong to the custom gauge in examples/themes/ornate_gauge.luau. They are not a separate theme package. Stretch the face only along its uniform horizontal axis. Keep the needle and end caps at fixed size; do not stretch or mirror them. The theme owns gauge metrics and colors. The custom control owns layout and behavior.
