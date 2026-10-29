### layoutSize

<!-- aliases: layoutSize | environment.layoutSize -->

`environment.layoutSize(node)` reads a node's size in layout pixels.

It returns a readable `Vector2`: the node's `AbsoluteSize` divided by the
UIScale factors above it. Call it on `UI.environment()` inside a component or a
Compose owner. While an ancestor page plays a `zoom` transition, the value
holds its last size at rest, so layout that depends on it does not change
during the zoom.
