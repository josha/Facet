# Facet Parity (Plan C) — task plan

Spec: `docs/superpowers/specs/2026-09-03-facet-parity-design.md` (the authority; this plan argues
from it). Goal prompt: `docs/plans/2026-09-03-facet-parity-goal.md`. Rules + traps:
`docs/plans/2026-09-02-facet-wicked-fast-reference.md`.

This is the design-level task plan. The executing session turns it into the code-level SDD plan
(`docs/superpowers/plans/2026-09-03-facet-parity-C.md`, superpowers:writing-plans format, full code
in every step) after reading the files named here — the line numbers below are at Facet `9213de5a`
(branch `wicked-fast-facet`) and drift as Plan B's T8/T9 land; re-locate by symbol, never by line.

## Global constraints (every task)

- Profile first. A lever is a lever only if C0's span for it is ≥5 % of the class it targets.
- Red-first COUNTER demonstrators. Wall-time is the report, never the gate. Every demonstrator also
  pins `stats.solves = N` for its tick (a viewport `env:set` is a full solve; a wrapper that
  captures only the last refresh proves nothing).
- Differential oracle after every step of every workload driver, both adapters, full device matrix
  incl. 320x640: `rectOf`, `screenRectOf`, hit rects, focus rect, engine `Position` per live
  instance — byte-equal to a forced full solve.
- Prop→dirty-class audit (`src/blueprint_schema.luau`) is load-bearing: any lane that skips work
  cites the class row that makes the skip a fact.
- Gates on every commit, FOREGROUND, one lune process at a time: `tools/test.sh`;
  `tools/verify.sh affected --jobs 1`; `python3 tools/check_source_size.py`; stylua. A frozen file
  (solver, renderer) gets a live seam extracted in its own commit before the change.
- RascalRally lockstep on every Facet `src/` change: RR suite + milestone canary + a contract test
  that pins the affected screens' `screenRectOf` numbers.
- No public API or behaviour change without the owner. `rectOf`/`screenRectOf` return today's
  numbers by construction (spec §5.1).
- Commit via `tools/commit_isolated.py --dry-run` then commit; never amend; nothing merged or
  pushed without the owner.
- Fresh-context adversarial review of every fix; RED-TEAM at the end.

## C0 — Baseline (the "before")

Files: FacetBench `tools/profile/attr.luau`, workload drivers, `docs/studio-runs/`.

1. If Plan B's T9 report exists (`FacetBench/docs/studio-runs/2026-09-02-wicked-fast.md`) with
   per-class rows for all five workloads on both runners, it IS the before; copy the table into
   `FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` §before. Otherwise run it: Lune + Studio,
   L (and M for the two small workloads), every class, median-of-K, ABBA against vide.
2. Add the missing vide rows: damage_fountain add/remove, nameplates add/remove.
3. Attribution spans per class on battle_hud/war_room/killfeed: measure / arrange / commit-by-walk /
   structuralSync-by-phase / adapter. This table decides which of C2–C5 are levers.
4. Counters present at HEAD: `stats.rectWrites`, `stats.solves`, `lastCommitVisits(byWalk)`,
   `ssPasses`. Add `stats.engineWrites` (fake + screen adapters, counted at the `Position` write)
   in C0 so the before-number exists.

Exit: the before table, spans, and a one-paragraph statement of which levers are ≥5 %.

## C1 — Per-host rect space

Files: `src/render/instance_boundary.luau` (`createOptsFor` :69-98, `kindOf` :105-125,
`parkEligible`); `src/layout/solver.luau` (`arrange` :2298, `translatable` :2334-2337,
`translateDescendants` :2235, call :2388) → seam `src/layout/translate_arm.luau` + pure
`src/layout/anchor_place.luau`; `src/render/renderer.luau` (`lastRects` :305, `rectOf` :317,
`screenRectOf` :465-491, `scrollShift` :382-408); `src/render/rect_pass.luau` (:83-96, :103-244);
`src/render/commit_walks.luau` (hitRects walk); `src/render/hit_lift.luau:80-149`;
`src/render/screen_target.luau:2077`, `src/render/screen_presentation.luau:333-402` (+ `settleRects`);
`tests/lib/fake_target.luau:524`; `docs/reference/api.md:2705, 2823-2857` (wording only if needed —
the numbers do not change).

Steps (each its own commit, each gated):

1. **Seams first.** Extract the translate arm from the solver into `translate_arm.luau` and the
   Anchor placement maths into `anchor_place.luau` (`place(parentRect, ownW, ownH, anchor, offsetX,
   offsetY) -> x, y`), with the mechanised read-vs-write seam test and byte-identical solver output
   on the whole suite. Source-size check green.
2. **Reader audit table** (in the ledger, before any store change): every `lastRects`/`rectOf` reader
   listed in spec §7 → "same space by construction" or "must compose via `hostOriginOf`". Each
   "must compose" gets a pinned test in this task.
3. **Red demonstrator** (`tests/perf/translate_host.spec.luau`): 250-plate scene, one all-translate
   tick. Pins at HEAD: `rectWrites = 1488`, `engineWrites = 1488`, `solves = 1`. Target pins:
   `rectWrites ≤ 250`, `engineWrites ≤ 250`, `solves = 1` (C6 later makes it 0).
4. **Translate-host trigger** in `createOptsFor`: reactive `offsetX`/`offsetY`/`anchor` + children
   → `{ instanceHost = true }`. Elision census re-recorded; nameplates instance count reported.
5. **Per-host store.** `hostOriginOf(path)` (cached, invalidated on host rect change);
   `screenRectOf` and `rectOf` compose it. Solver arranges beneath a host from (0,0); `translatable`
   on a host root skips `translateDescendants`. `rect_pass` unchanged. `hit_lift` overlap composes.
   Adapters: `applyRect` host maths collapses (`host.ox = 0` for host-space input); fake target
   models the same parenting and records `Position` for the oracle. Oracle extended and green on
   the full matrix, both adapters.
6. **Unify or scope.** Try all host kinds under one rule and retire `settleRects`. Measure. Ruling:
   keep if neutral-or-better on every class; else translate hosts only, `settleRects` stays.
7. **Recycling.** Measure nameplates/damage_fountain add/remove. If >5 % worse than C0, add a
   "host" `kindOf` bucket and let plain-Frame hosts park. Re-measure.
8. **RR lockstep.** Every RR screen with reactive placement (minimap markers, sponsor cards, recap
   marquee) gets a `screenRectOf` pin before step 5 and again after; RR suite + milestone canary.
9. Studio matrix on nameplates (tick, add, remove) + battle_hud updateItem; record.

Exit: demonstrator green at ≤250/≤250; oracle green; suites ≥ floors; RR green; census recorded;
tick number Lune + live beside vide.

## C6 — The translate lane

Files: new `src/render/translate_lane.luau`; `src/render/renderer.luau` `dirtyScan` :2836-2895
(the lane hook only — one call); `src/layout/anchor_place.luau` (reused, not copied);
`src/blueprint_schema.luau:763-780` (the class rows the lane cites).

1. Red demonstrator: same 250-plate tick pins `solves = 0`, `laneTranslates = 250`,
   `rectWrites = 250`, `engineWrites = 250`, `lastCommitVisits = 0`. A mixed tick (one plate also
   changes `text`) pins `solves = 1`, `laneTranslates = 0`.
2. Lane: all dirty entries are placement props on translate hosts → per host
   `anchor_place(parentSpaceRect, w, h, anchor, ox, oy)`, `lastRects[host]`, host hit entry,
   `hostOriginOf` invalidation, one `adapter.setRect`. Store update first, engine write second, so a
   reader between ticks sees the new number. Never partial: any non-placement dirt → normal path.
3. Oracle after every lane tick (forced full solve must agree byte-for-byte — including the
   host's children through `screenRectOf`).
4. Focus/scroll-into-view/hit under a lane-moved host: pinned tests (focus ring follows, hit test at
   the new place succeeds, old place fails).
5. RR lockstep + Studio nameplates tick; report beside vide 0.29 with the ratio.

Exit: nameplates tick ≤1.0 ms Lune with `solves = 0`; live number recorded.

## C2 — Measure pruning (Plan B's O1)

Files: `src/layout/solver.luau` `measure` ~:1602 + `adopt` :1735-1745 + `memoPlans` :3466;
`src/layout/measure_facts.luau:408-410`. Seam first if the solver cap is hit.

1. Red: battle_hud L, 1 leaf `text` dirty → pins `work.visited = 5115` at HEAD; target
   `work.visited ≤ depth × k` (state the k from the tree; ≤ 64).
2. `adopt` before the per-kind body; a clean subtree returns at its root. `memoPlans` survives
   solves, invalidated along the dirty path (and on env/viewport/theme change: full clear — the
   check-that-proves-nothing trap).
3. Oracle full matrix. Registry-neutrality specs (24 of them go red on an unowned memo — own it on
   the scope).

Exit: 0-dirty solve visits ≤ depth; update classes re-measured.

## C3 — Stack arrange O(dirty)

Files: `src/layout/stack.luau:96-183` (loop :127-157); solver arrange entry for stacks.

1. Red: 1-leaf update in a 1,000-child stack pins `work.arrangeVisits = 1000` at HEAD; target = 1
   when the child's size is unchanged, `= (n − i)` when child i grew.
2. Arrange from the first size-changed child; a size-unchanged dirty child is a no-op for siblings.
   Cites the measure-vs-arrange class rows.
3. Oracle full matrix; war_room reorder/remove re-measured (the per-rect constant is the report).

## C4 — Dirty-child index (Plan B's O5)

Files: `src/render/commit_walks.luau` (`skip`/`probeEntry` :370-443, moveBlind :361-368);
`src/render/renderer.luau` commit walks :2140-2228.

1. Red: 1-leaf update pins `lastCommitVisits.byWalk.*` ≈ 64 each at HEAD; target O(depth) (≤ 8).
2. Per-node dirty-child set built in `dirtyScan`; walks descend by the set. Eight walks, one index.
3. Oracle; update classes re-measured live.

## C5 — Bound `syncZOrder` + `collectRetiringRoots` (profile-gated)

Files: `src/render/renderer.luau:2384-2409`, `:2671`; the retiring-roots collector.

Only if C0/C1 spans show ssZOrder ≥5 % of a structural class after C1 (per-host spaces make z a
per-host rank). Red: add one plate → `ssZOrderVisits = N` at HEAD; target O(host subtree). Else
book it with the number.

## C9 — Closing

Full matrix Lune + Studio, ABBA vs vide, chart, report
`FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` (per class: before / after / vide / target /
met-or-miss, misses named with their remaining mechanism), RED-TEAM, RR canary, whole-branch review,
memory + `tasks/lessons.md`, then `superpowers:finishing-a-development-branch` (owner picks).
