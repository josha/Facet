# Components

A component is a function returning a native Instance. Create controls through
`Facet.controls(runtime)` and native objects through `Host = runtime.constructors`.
Use constructor names or `Name`, numeric children and native property names.

Keep view state in Compose.cell, calculations in Compose.formula, side effects in
Compose.watch and external teardown in Compose.cleanup. Bind a readable directly
or use a `function(use)` property body. Callbacks command model state.

Use Compose.show, keyed, portal, LayerStack and presence directly. Use stable keys
and current-item readables. Keep durable row state outside windowed row owners.
Use runtime.spring/tween/timeline for motion and respond to reduced-motion facts.

No Facet object owns an application, mount list, render target or scene. Native
target Instances belong to the caller's Compose tree. Control `ref` callbacks
receive their native root Instance.

See [the working screen](03-getting-started.md) and [API](../reference/api.md).
