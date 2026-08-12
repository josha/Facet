# Hosted row-actions for VirtualList — design (row-actions perf mission)

**Status: ACCEPTED 2026-08-12** (scoping pass over
`docs/plans/row-actions-perf-mission.md`; measurements below). Supersedes the
charter's open A-vs-B question.

## The pick, and why neither charter path survived contact

The charter offered (A) a VirtualList gesture-composition hook mirroring
`table.luau`'s `externalGesture`/`composeWithReorder`, or (B) generic cell
recycling in `virtual_list.luau`. Task 11b's own instance experiments
(0/2/3/5 extra instances) price each wrapper instance at ~0.1ms steady /
~0.26ms fling per refresh:

- **A alone fails the time budget.** Dropping only the Hit Grip (5→4) leaves
  Anchor+Content+2 Whens ≈ +45% steady — the 3-instance experiment already
  measured 1.622ms vs ~1.10ms baseline.
- **B alone fails the instance budget.** Recycling never removes the 5
  wrapper instances from the tree; the ≤4 census ceiling stays red. And the
  renderer-level instance recycling Step 9 shipped (ON by default) is already
  in these numbers — the cost is the framework's per-node mount work, not
  only engine `Instance.new`.

But the hook removes the objection that killed the cheapest shape. The
charter ruled out defer-until-touched because pointer capture could not
survive the wrapper mounting under the touched row. With the gesture riding
**VirtualList's own per-row `Hit` Button — which never remounts —** capture
survival is free, and the whole wrapper becomes deferrable. So the pick is A,
extended to its fixed point:

## Hosted mode: a closed row mounts NOTHING

`newVirtualList` gains `spec.rowActions` (mirroring Table's integration).
When present:

1. **Shared dispatcher, not per-row closures.** VirtualList wires the SAME
   four `onPointerDown/Move/Up/Cancel` functions onto every row's existing
   `Hit` Button. Handlers receive the hit's path; the dispatcher maps path →
   row key → engine. A closed row's whole marginal mount cost is four static
   props on a node that already mounts.
2. **Lazy engine.** The row's gesture/state engine (extracted from
   `row_actions.build` — state machine, axis lock, velocities, coordinator
   claim, commit) is built on FIRST pointer-down on that row, never during
   scroll. Built with `externalGesture` semantics: no Hit Grip, ever.
3. **Slide rides the presentation channel.** The engaged row's content is
   translated via `controller.setPresentationOffset` (ADR-0022 presentation
   authority — DropLine/drag-ghost precedent), not a per-row layout
   `offsetX` prop. Disengaged rows declare no reactive prop at all. (The
   first floor experiment measured the per-row memo + reactive offsetX
   variant at +6.7–8.8% fling — that shape is rejected, not just unchosen.)
4. **One shared tray overlay per list, not per row.** The one-open
   coordinator policy means at most one row is ever engaged, so the trays
   live in ONE `UI.When` overlay inside the canvas (after the rows ForEach,
   so tray Buttons are natively tappable in the revealed strip), positioned
   at the engaged row's canvas offset, built from the engaged row's action
   specs via the extracted tray builder. Per-row cost: zero; per-list cost:
   one closed `When` frame, amortized over the window (~0.08 nodes/row
   measured).
5. **Commit height** drives the engaged row's `rowHeightDim` through a
   VirtualList-internal override seam (the engine's collapse animation);
   engaged-only, so scroll paths never see it.
6. **Unchanged elsewhere.** Standalone and Table modes are byte-untouched —
   the ~250 hardcoded `Anchor/Content/Hit` test paths stay valid; hosted
   mode gets its own path helpers (Table-mode precedent:
   `tests/table.spec.luau`'s `wrappedRowHitPath`). `reorderable` +
   `rowActions` on the same list is an explicit error in v1 (VL reorder
   rides declarative `UI.draggable`; composing it with the raw-handler
   funnel is its own future task).

## Measured floors (this machine, 3-run means, `perf_floor_experiment.luau`)

| Shape | Steady | Fling | Nodes/row |
|---|---|---|---|
| Today's wrapper (5 instances) | +41–59% | +82–90% | 5.00 |
| Per-row memo + reactive offsetX floor | +1–2% | +6.7–8.8% | 0.08 |
| Lean floor (shared dispatcher, presentation slide) | −0.7–1.7% | +4.8–7.1% | 0.08 |
| **A/A control (two IDENTICAL worlds)** | −6.2–1.8% | **+1.7–5.2%** | 0 |

The A/A control shows the committed workload's fixed build/measure order
(baseline first, wrapped second) carries a systematic ~2–5pp second-world
bias on fling. The lean floor is inside the A/A band — true marginal cost
~1–2%. **The workload must be de-biased (interleave or order-swap the two
worlds' measurement passes, same drive shapes) for a ≤5% ceiling to be a
real gate**; that fix ships with this mission and is disclosed in the
device-matrix evidence.

## What must be proven before ship (charter requirements)

- Differential mount-identity proof (incremental-layout precedent): a hosted
  list with rowActions, all rows closed and untouched, produces an
  instance tree identical to an unwrapped list except the one overlay node;
  and engaging/disengaging a row returns the tree to that state.
- Behavior parity: swipe reveal both edges, full-swipe commit, irrevocable
  commit semantics, one-open coordinator, scroll-close, outside-tap close,
  keyboard Delete, `fullSwipe` — each with hosted-mode tests mirroring the
  standalone suite's semantics (the 100+ existing tests stay the net for
  the shared engine).
- Budget restored under the (de-biased) committed workload: ≤5% steady, ≤5%
  fling, ≤4 instances; `check_row_actions_matrix.py` ceilings tightened to
  5/5/4 with mutation-bite proof.
