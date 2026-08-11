# Row-actions perf mission — scoping

**Status: NOT STARTED.** A charter to seed a future brainstorm, not an
implementation plan. Distilled from `.superpowers/sdd/row-actions-implementation/
task-11b-report.md` and the "Task 11b" section of
`artifacts/row-actions/device-matrix.md`. The `row-actions` gate
(`tools/lune/gate_manifest.luau`) is re-baselined to the numbers below
(director ruling 2026-08-11) rather than blocked on this mission; closing it
is what would let a future gate tighten the ceiling back toward the plan's
original ≤5%/≤4 budget.

## The problem, measured

A `newRowActions`-wrapped row, CLOSED, inside `newVirtualList` (200 rows,
13-row window, `bench/perf_scenes.luau`'s own `lab-dense-scroll` drive shape,
`artifacts/row-actions/perf_workload.luau`):

| | Baseline | Wrapped (`c61f00a`) | Wrapped (`17719bc`, current) | Budget |
|---|---|---|---|---|
| Steady scroll (mean, ms/refresh) | ~1.10ms | 1.73ms (+59%) | 1.75ms (+57%) | ≤5% |
| Fling (mean, ms/refresh) | ~1.60ms | 3.04ms (+88%) | 3.01ms (+81%) | ≤5% |
| Idle (no window-membership change) | ~0.008ms | 0.016ms (+136%) | 0.018ms (+102%) | informational |
| Wrapper instances / closed row | — | 5.00 | 5.00 | ≤4 |

Idle cost is genuinely near-free in absolute terms (~0.0007ms/row) — the
"closed = inert" directive holds there. The gap is entirely in **mount-time**
cost: every row that crosses the virtualization window boundary pays for
creating, measuring, and later destroying 5 extra `Instance`s.

## What Task 11b's profiling ruled out

Instrumented phase timing showed `row_actions.build()`+`dispose()`'s own
Luau-side work (signals, memos, gesture closures, text measurement) is only
**~2% of the measured wall-time delta**. Three controlled experiments varying
only wrapper Instance count (0 / 2 / 3 / 5 extra instances, everything else
held constant) proved the lever is **Instance materialization**, not the
reactive graph: 0 extra instances recovers ~all of the gap to baseline; 5→3
(dropping just the two tray `When`s) recovers only a small fraction.

## Why it can't be cut further inside `row_actions.luau` alone

`Anchor` (root) → `Content` (ZStack) → `Hit` (Grip) is a load-bearing path
structure: ~250 call sites across `tests/row_actions.spec.luau` and
`tests/row_actions_input.spec.luau` hardcode those paths for pointer/focus
injection. True defer-until-touched (0 instances until first gesture) needs
the initial pointer-down capture to land on an `Instance` that later becomes
a child of a new `Anchor` — a reparent this framework has no primitive for
without destroy+recreate, which cannot survive an in-flight pointer capture
(the same constraint `table.luau`'s `composeWithReorder` already works around
by replaying onto an existing captured Instance rather than handing capture
between two). Merging the two tray `When`s (5→4) is legal but recovers only
~15-20% of the delta — not worth the mechanical rewrite of ~250 hardcoded
paths for a change inside this environment's own ±10-15-point run-to-run
noise band.

## The actual closure path: a VirtualList gesture-composition hook

`table.luau` already has this for its own rows: `composeWithReorder` lets
Table drop `row_actions`' own `Hit` Grip entirely and drive the composite off
Table's existing row hit surface. `virtual_list.luau` has no equivalent seam
today — a `newRowActions` caller wrapping a `VirtualList` row cannot avoid
mounting its own capture surface. Building one (mirroring
`externalGesture`/`composeWithReorder`) would remove the dominant-cost
`Hit` Grip for `VirtualList` consumers the same way Table already avoids it.

This is **cross-cutting to every `VirtualList` consumer**, not row-actions-
specific, and belongs to its own mission. A second, larger-scoped
alternative — generic cell recycling in `VirtualList` (reusing mounted
Instances across window-membership changes instead of destroy+recreate),
in the shape of the Step 9 performance lab's own recycling work — would
close the gap for every wrapped-composite shape, not only row-actions, at
correspondingly larger cost/risk.

## Target

Restore the ≤5%/≤4 budget for a two-edge wrapped row under the same
`perf_workload.luau` drive shape, via whichever of the two paths above a
future scoping pass picks — including a differential-mount-identity proof
(the incremental-layout mission's own precedent) before either ships.
