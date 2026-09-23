# Choosing the abstraction

Facet is appropriate when an application needs reusable Roblox UI behaviors such as editable inputs, adaptable navigation, modal focus, virtual collections and themed controls while retaining direct access to Compose and engine composition.

Use Compose Roblox constructors for scene construction and native primitives. Use Facet when a control supplies interaction policy the primitive alone lacks. A frame, layout, ScreenGui, part, camera or binding does not need a Facet wrapper.

A screen built from native Frames and UIListLayouts alongside Facet controls is the intended architecture. Its ownership, structural changes and animation still use Compose. Game-specific state machines and networking stay outside the UI library.

Facet does not provide a portable rendering backend, its own general layout engine, a separate signal type or an application owner. If those are requirements, they require an explicit architecture decision outside this package.

See [architecture](02-architecture.md), [the public contract](../reference/api.md), and [choosing controls](14-choosing-controls.md).
