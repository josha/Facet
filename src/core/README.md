# Facet on Compose

Facet has no reactive runtime of its own. State is `Compose.cell`, derivation is
`Compose.formula`, observation is `Compose.watch` / `owner.watchStatic`, lifetime
is a Compose owner, and batching is the reactor's. There is no Facet signal, memo
or scope type, and no second graph, observer queue or Signals bridge.

## What is in this directory

`services.luau` builds the per-application service bag. It carries no reactive
API. It holds Compose's reactor, the application's root owner, the error
boundary, and the layout settle pass. A surface's nodes mount into the UI
runtime `render/compose_scene.luau` builds; `core.adopt` puts the same settle
pass and the same boundary on that runtime's reactor too.

`on_change.luau` wraps `owner.watchStatic` and suppresses registration and
equal-value deliveries, because a Facet change listener reacts only to a new
value. Compose's watch delivers once when it is created.

`contract.luau` exports `Cell<T>`, `Formula<T>`, `Readable<T>` and `Owner`, and
`src/init.luau` re-exports those names. Cell, Formula and Owner are Compose types;
Readable describes the read-only shape accepted by Facet and includes the
concrete Compose Cell and Formula types. They exist so a typed helper or an out-of-repo
control can name a Compose value without requiring the vendored snapshot. They
are an interop spelling, not an authoring API: write `Compose.cell`,
`Compose.formula` and a Compose owner. `contract.luau` also declares `Core`, the
shape of the service bag `services.luau` builds.

`profile.luau` is the span accounting the perf lab reads; it is not reactive.

## Error containment

A throwing binding must not take a surface down. `services.new` guards the
application owner with a Compose boundary, so a watch body that throws is caught
and reported rather than unwound into whoever wrote; every child owner inherits
it, and `core.guard(owner)` applies it to an owner created outside that tree. A
drain that throws is contained at the reactor's own `settle`, because the writer
that opened it is ordinary application code with no way to handle another node's
failure. The last valid value stays painted, because the binding that failed
delivered nothing. `core.lastError()` reads the last contained failure; it is
sticky and never cleared.

## Layout settling

Geometry feeds back: a surface solves, publishes what it measured, and the
publication can change what it must solve. `render/settle_pass.luau` drives that
to a fixed point inside the flush that opened it, so a top-level `env:set`
returns with the surface solved. Callbacks run after the drain in registration
order; one that writes ends the pass and the pass restarts from the first, until
a pass writes nothing, under a 100-pass cap. "Wrote something" is Compose's own
write clock. Compose drains watches but has no hook for untracked terminal work,
so the pass decorates the reactor instance Facet owns; the vendored source is
never touched.

## Native scheduling contract

- Delivery is dependency-registration FIFO, not a total node-creation sort.
- A drain is capped at 1,000,000 watch runs; the settle pass has its own 100-pass
  cap. Compose abandons remaining work at its cap and lets a later source write
  wake the affected watches.
- A formula that throws keeps its cached value and the dependencies it reached
  during the failing run. There is no rollback to the previous dependency set.
- Reactive bodies and batches must be synchronous.

## The pin

The exact pin and integrity inventory live in `../vendor/compose`. The generated
source snapshot is committed and read-only, with no Facet patch overlay. Test and
verification entry points check it against the lock without rewriting it. A fresh
clone builds offline; the full MIT notice travels in the package.
These internals are not consumer entry points: use the Facet table and the
documented client modules.
