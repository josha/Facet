# Architecture

## The control factory

`Facet.controls(runtime, options)` makes the control constructors for one
Compose Roblox runtime. A control constructor uses the native constructors of
that runtime and returns an Instance. Compose owns the properties, events,
children and cleanup directly.

`Facet.app(options)` prepares that runtime, the controls, a native ScreenGui
and its StyleSheet. Its mounts use `runtime.mount`. It does not add a scene
graph or a scheduler. `app.dispose()` stops its mounts and disposes a runtime
only when the app created it. A caller-supplied runtime remains caller-owned.

## The data path

Data moves in one path: model cell, then Compose binding, then native Instance
property. Roblox does the layout and the paint. There is no intermediate Facet
node, dirty queue or renderer. Compose owns property observation, clocks,
scheduled work and readiness tracking. Facet supplies control policy to those
mechanisms, such as waiting for native text and overlay bounds before reveal.

Callbacks command model cells. Property functions read those cells through
`use`; a resize or model update changes the bound native properties without
rebuilding the screen. Direct native writes inside a control can apply input,
selection or scroll policy. Their subscriptions and work must have a Compose
owner; they must not create a second source of model state.

## Composition

- Use `Host = runtime.constructors` for engine objects. Examples are ScreenGui,
  SurfaceGui, BillboardGui, ViewportFrame, UIListLayout, UIGridLayout and
  constraints.
- Use `Compose.show`, `Compose.keyed`, `Compose.portal` and
  `Compose.LayerStack` for composition.
- Use the Compose animation APIs for motion.

UI and 3D content use the same runtime and the same ownership rules.

Create optional decoration with `Compose.show` when the theme first needs it.
Retain reusable art for later theme changes. A plain reactive theme must not
allocate image bounds and geometry subscriptions before it has image art.

Use known container width when a control first creates responsive content.
Keep that content while native bounds are zero during mounting. Native size
observations correct the layout when bounds arrive. Small overlay measurement
sets use `runtime.observe` directly, so placement does not wait for another
frame. High-volume geometry observations can use Compose frame coalescing.

`UI.Composition` selects among the native forms supplied to `UI.Region`.
Roblox measures the forms. Facet uses their bounds and declared ranks to
choose a form, land a top-bar region or drop an optional region. This is HUD
adaptation policy, not a replacement for native layout or text measurement.
The model supplies the forms; it does not run a separate resize loop.

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
