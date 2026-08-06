# Incremental layout — scoping

**Status: STAGES 1 AND 2 DONE. Stage 2 ships ON by default (v2 — skip subtrees inside one solve; see optimization-log L-16). Stage 3 not started.** This is a mission, not a patch. It changes the solver's
central contract, and the last two caches added to that same function were both wrong in
ways only a differential oracle could see.

## The problem, measured

`renderer.solveAndApply` calls `solver.solve(root)` — a full solve from the root — on
every dirty pass that touches `measure`, `arrange` or `structure`. So:

| event | nodes arranged | p50 (Studio, M4, 360×691) |
|---|---|---|
| viewport resize | 121 | 3.46 ms |
| **one bound value changed** | **121** | **1.27 ms** |

A ticking counter costs what a rotation costs. At the estimated 22× gap to a Fire HD 8
that single-value change is ~28 ms — a dropped frame at 30 fps for one character.

**The reactive core is already fine-grained.** `tests/fine_grained_reactivity.spec.luau`
proves a single-row write produces a constant number of renderer writes at 200 / 2 000 /
20 000 rows. The *write* path is right. The *solve* path has no granularity at all.

## The design: relayout boundaries

The standard answer (WPF's measure/arrange invalidation, Flutter's relayout boundaries):

1. **Dirty marking.** A prop change marks its node `measureDirty`. Today the renderer
   already classifies dirt into `structure` / `measure` / `arrange` / `paint` /
   `semantics` — the classification exists; only the *scope* of the response is wrong.

2. **Upward propagation, stopped at a boundary.** Re-measure the dirty node. If its
   resulting size is **unchanged**, nothing above it can move: stop, and re-arrange only
   that node's subtree. If the size changed, mark the parent dirty and repeat.

3. **A node is a relayout boundary when its size cannot depend on its children.** That is
   exactly the predicate L-9 already computes for one axis: a `fixed` dimension, or a
   `percent`/`fill` dimension inside a bounded parent, cannot change because a child did.
   `ctx.heightFree` is the same shape of reasoning and is already in the solver.

4. **Arrange only the affected subtree**, re-basing at the boundary's own rect.

## What makes this hard here, honestly

- **`ctx.compact`, `ctx.textFacts` and `ctx.textStates` are last-write-wins across the
  whole solve.** A partial solve visits a different set of nodes in a different order, so
  those published verdicts change even when geometry does not. This is not hypothetical:
  it is precisely the BLOCKER a differential fuzz caught on the measure memo (L-9 header
  and `tests/measure_memo.spec.luau`), and a partial solve is a much larger version of
  the same hazard.
- **`ViewThatFits` / the compact ladder / `Composition`** choose a form from the offer.
  A subtree re-solve must reproduce the same offer, or a candidate silently flips.
- **Scroll canvases** derive content extent from the full child set.
- **Diagnostics** are accumulated per solve; a partial solve must not drop findings for
  nodes it did not visit, or `controller.diagnostics()` — the thing that catches every
  layout defect in this repo — goes quiet exactly when the tree is partially stale.

## Verification plan (non-negotiable, given the above)

1. **Differential fuzz, incremental vs full**, over seeded trees: compare every rect
   **and** `compact`, `truncated`, `textState`, plus the diagnostics list. Geometry alone
   proves nothing — that lesson is already paid for.
2. **Mutation-prove the oracle** before trusting a green result: deliberately break the
   boundary rule and confirm the fuzz reddens. L-10's differential was green against a
   broken build until the trees were made ragged.
3. **The existing suite unchanged** — 3 405 cases, plus RascalRally's 3 089.
4. **`resize-relayout` is the acceptance measurement**: `arrangedPerDataChange` must fall
   well below `arrangedPerResize`; the ratio is already reported by the workload and
   currently reads 1.00.
5. **Live Studio canary** at phone portrait with the layout audit armed.
6. **`tools/studio/visual_diff.luau`** — engine-resolved geometry for every GuiObject,
   full vs incremental. Built and proven stable (155 nodes, 0 differences under no
   change) ahead of Stage 2; it is the oracle Stage 2 has to satisfy.

## Stage 1 result — the prize, measured

`solver.solve(..., { analyzeBoundaries = true })` records, per node, whether its own
size can change because something inside it changed. `solver.boundaryReport` then walks
each node up to its nearest absorbing ancestor and counts that subtree — i.e. **how much
a boundary-aware layout would redo for a single change**. Exposed as
`controller.analyzeBoundaries()`; it runs only when called, so an ordinary frame pays
nothing.

Measured on the real workload (dense-scroll, 360×691, compact three-band row):

| | |
|---|---|
| nodes in the tree | **104** |
| nodes that ABSORB a size change | **28** |
| nodes re-arranged for one change **today** | **104** (the whole tree) |
| ...with boundaries honoured | **20** — mean, median *and* p95 |
| share of the tree | **19%** |

**A 5.2× reduction, and the distribution is flat** (mean = median = p95 = 20), so the win
is uniform rather than concentrated in a few lucky nodes. Every change benefits about
equally, which is the best possible shape for Stage 2.

Carried to the timings from L-12: one bound value at 1.27 ms p50 would become ~0.24 ms;
at the estimated 22× device gap, ~28 ms becomes ~5.4 ms — a dropped frame becomes a
comfortable one.

**Recommendation: proceed to Stage 2.**

## Suggested staging

- ~~**Stage 1 — boundary detection only.**~~ **DONE.** 19% of the tree, 5.2× — see above.
- **Stage 2 — skip arrange when nothing resized.** *(IMPLEMENTED 2026-08-05, opt-in via
  `incrementalLayout = true`, OFF by default. Root cause of the first attempt's failure:
  `result.rects[id]` is a RECORD (`{ rect, kind, textState, compact, textFacts }`), not a
  rect — see optimization-log L-14/L-15. Works and is measured: `lastArranged` 141 → 20
  in Studio, 87 → 4 headless, with an engine-level visual diff over 185 nodes showing
  zero differences. **Turning it on reddens ten existing cases** — `theme_value_displays`,
  the rung-3 gauge, and a moving-target motion case. Those ten are the next pass's
  specification. The differential fuzz over seeded trees called for in step 1 below was
  NOT built; one hand-made fixture passed and the suite immediately found counterexamples,
  which is the whole argument for the fuzz.)* The narrow case: if a dirty node
  re-measures to the same size and no structural change occurred, re-arrange only its
  subtree. Covers the ticking-counter case, which is the one that costs a frame today.
- **Stage 3 — full boundary propagation.**

Stage 1 is done and answered the question: 5.2x, uniformly distributed. Stage 2 is next,
and it is where the risk starts — see "What makes this hard here" above.
