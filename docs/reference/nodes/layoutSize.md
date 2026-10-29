### layoutSize

<!-- aliases: layoutSize | UI.layoutSize -->

`UI.layoutSize(node) -> ReadOnlyValue<Vector2>` reads the size of `node` in
layout pixels: its `AbsoluteSize` divided by the UIScale factors above it.
Call it inside a component or a Compose owner. While an ancestor page plays a
`zoom` transition, the value holds its last size at rest, so layout that
depends on it does not change during the zoom.

For example, `UI.layoutSize(panel)` inside a component returns a readable that a
layout formula can `use` to choose a compact arrangement.
