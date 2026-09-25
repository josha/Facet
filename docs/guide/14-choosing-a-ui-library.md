# Choosing the abstraction

Use Facet when an application needs reusable Roblox UI behaviors and also
needs direct access to Compose and engine composition. Examples of these
behaviors are editable inputs, adaptable navigation, modal focus, virtual
collections and themed controls.

## Facet or native primitives

Use the Compose Roblox constructors to build the scene and the native
primitives. Use a Facet control when it supplies interaction policy that the
primitive does not have. A frame, layout, ScreenGui, part, camera or binding
does not need a Facet wrapper.

A screen that mixes native Frames and UIListLayouts with Facet controls is the
intended architecture. That screen still uses Compose for ownership, structural
changes and animation. Game-specific state machines and networking stay outside
the UI library.

## What Facet does not supply

Facet does not supply:

- a portable rendering backend,
- its own general layout engine,
- a separate signal type,
- an application owner.

If you need one of these, make an explicit architecture decision outside this
package.

See [architecture](02-architecture.md), [the public contract](../reference/api.md)
and [choosing controls](14-choosing-controls.md).
