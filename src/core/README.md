# Facet’s Compose runtime

`Facet.newCore` uses `compose.luau`. Native Compose cells and formulas are the
readables themselves; native watches and the reactor handle dependency delivery,
batching and scheduling. Native owners store cleanup and unlink children in
constant time. There is no second reactive graph, ordered observer queue, foreign
Signals bridge or retained Signals export/vendor. `custom.luau` is only the old
internal module-path alias used by development fixtures.

Facet retains NaN-safe equality, counters, explicit readable disposal, diagnostics,
component getter tracking, and layout settling. Layout settling repeats after
geometry publication; Compose’s `reactor:settle` only drains reactive work and
cannot replace that renderer phase. Formula disposal uses pinned graph internals
because the public formula API has no disposal method.

## Native scheduling contract

- Delivery is dependency-registration FIFO, not a total node-creation sort.
- A drain is capped at 1,000,000 watch runs; layout has its separate 100-pass cap.
  Compose abandons remaining work at its cap. Dispose and re-register affected
  watches, or remount their owner, to resume. Changing a cell alone can leave an
  abandoned watch stale. This is a limitation of the pinned upstream runtime.
- Failed formulas keep their cached value and dependencies reached during the
  failing run; a changed read sequence can drop old edges before failure. There
  is no rollback to the previous successful dependency set.
- Reactive callbacks and transactions must be synchronous. Components keep their
  public state/getter API. `Facet.Signals` and raw Signals getter interop are removed.

## Ownership and composition

`scope_impl.luau` delegates storage and child unlinking to Compose owners. Facet’s
structural reconciler remains because it retains exiting rows, supports identity
on re-entry, and publishes a consistent surviving tree when a row factory throws.
Compose’s host/block keyed reconciler has different lifetime and failure behavior;
substituting it would change those visible features, not just replace bookkeeping.

The source pin, full MIT notice, two local lifetime fixes and exact integrity
inventory live in `../vendor/compose`. `tests/compose_lifetime.spec.luau` covers
final-listener detachment, reads after self-disposal, and cap re-registration.
These internals are not consumer entry points. Use the Facet table and documented
client modules.
