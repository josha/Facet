# Architecture

## The control factory

`Facet.controls(runtime, options)` makes the control constructors for one
Compose Roblox runtime. A control constructor uses the native constructors of
that runtime and returns an Instance. Compose owns the properties, events,
children and cleanup directly.

## The data path

Data moves in one path: model cell, then Compose binding, then native Instance
property. Roblox does the layout and the paint. There is no intermediate Facet
node, dirty queue, renderer or settle pass.

## Composition

- Use `Host = runtime.constructors` for engine objects. Examples are ScreenGui,
  SurfaceGui, BillboardGui, ViewportFrame, UIListLayout, UIGridLayout and
  constraints.
- Use `Compose.show`, `Compose.keyed`, `Compose.portal` and
  `Compose.LayerStack` for composition.
- Use the Compose animation APIs for motion.

UI and 3D content use the same runtime and the same ownership rules.

## Virtual collections

The virtual controls give native viewport facts and measured content sizes to
`Compose.OrderedCollection`. Compose calculates placement, extent, identity and
anchor adjustments. The control applies `desiredOffset` to `CanvasPosition`.
Compose pools own the reusable row containers. Facet has no separate prefix
index or anchor algorithm.

## Control-specific policy

Facet keeps an algorithm only when the platform has no equivalent. Examples are
radial choices, value validation and adaptive presentation. Native selection
and input contexts apply these policies. There is no general Facet focus graph.
