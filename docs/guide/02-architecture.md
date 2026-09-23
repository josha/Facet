# Architecture

`Facet.controls(runtime, options)` builds a control vocabulary for a Compose Roblox
runtime. Constructing a control uses that runtime's native constructors and returns
an Instance. Compose owns properties, events, children and cleanup directly.

The data path is model cell → Compose binding → native Instance property.
Roblox performs layout and paint. There is no intermediate Facet node, dirty
queue, renderer or settle pass.

Use `Host = runtime.constructors` for engine objects, including ScreenGui,
SurfaceGui, BillboardGui, ViewportFrame, UIListLayout, UIGridLayout and constraints.
Use Compose.show/keyed/portal/LayerStack for composition and its animation APIs for
motion. UI and 3D use the same runtime and ownership rules.

Virtual controls supply native viewport facts and measured content sizes to
Compose.OrderedCollection. Compose supplies placement, extent, identity and anchor
adjustments; the control applies desiredOffset to CanvasPosition. Compose pools own
reusable row containers. No Facet prefix index or anchor algorithm runs alongside.

Control-specific algorithms remain where the platform has no equivalent, including
radial choices, value validation and adaptive presentation. Native selection and
input contexts implement those policies without a general Facet focus graph.
