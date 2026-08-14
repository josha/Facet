# ADR-0026 — authored opacity/scale/rotation: headless measurement

**Tier: headless Lune. That is a REGRESSION SIGNAL, never a device claim** (round-3
standing rule 3). The three tiers, unchanged: headless Lune = regression signal;
MicroProfiler in Studio = real engine work with real instance counts; a physical device
run = the only thing that supports a device claim. Rows below carry the first only.

Harness: `tests/zz_adr0026_perf.luau` (temporary, deleted after this record; the durable
instrument is the perf lab's `motion-flight` pass, which now carries the same arms —
`examples/performance/lab/perf_lab.luau`, gated by `tests/perf_lab.spec.luau`).

24 rows, 9 repetitions, 90-frame cap, per-frame `presenter.tick` + `presenter.refresh`
in ms, median of per-rep medians. Arms, in order: **A** idle · **B** position flight ·
**C** position+size · **D** authored paint · **B′** position flight again · **A′** idle ·
**P** a second mount whose rows declare none of the three.

## The control comes first, because that is the rule

| control | run 1 | run 2 | run 3 | run 4 |
|---|---|---|---|---|
| **B/B′ same-arm flight spread** | 0.0001 | 0.0035 | 0.0062 | 0.0040 |
| per-rep range of arm B alone | — | 0.0317 | — | — |

**The noise band is therefore ~0.006 ms/frame at the arm level and ~0.03 ms/frame at the
repetition level.** Nothing below that is a result.

## The arms

| arm | run 2 | run 3 | run 4 |
|---|---|---|---|
| A idle (triple DECLARED, at rest) | 0.0010 | — | — |
| P idle (triple ABSENT) | 0.0010 | — | — |
| **off-path delta (A − P)** | **0.0000** | 0.0000 | 0.0000 |
| B position flight (24 records) | 0.1018 | — | — |
| C position + size (24 records) | 0.1022 | — | — |
| D **authored paint** (24 records) | 0.1088 | — | — |
| **D − B** | **+0.0069** | +0.0057 | +0.0046 |
| C − B (the size half, for reference) | +0.0003 | +0.0024 | +0.0037 |

All three arms seed the **same 24 records**, which is what makes D − B the marginal cost
of the paint half rather than the cost of a bigger experiment.

## What the numbers say, and what they do not

**D − B is 0.0046–0.0069 ms/frame against a same-arm control of 0.0001–0.0062. It is
inside the noise band.** The honest statement is therefore *"no per-frame cost measurable
on this instrument at 24 records"* — **not** "the paint half is free". Three round-2
"improvements" evaporated when measured properly and this row is written so this one
cannot join them.

**The off-path delta is 0.0000 across every run**, with both idle arms sitting on the
clock's own resolution floor (0.0010 ms). Two things support the claim independently of
that floor, and they are the stronger evidence:

- the renderer's gate is `authoredN > 0`, checked **before** any table lookup, and
  `presentation.composeTransform` returns the channel value **by identity** when nothing
  is authored — no allocation, no field comparison;
- `tests/authored_presentation.spec.luau` asserts that a surface declaring none of the
  three emits **no `transform` or `transparency` adapter write at all**, and that check
  was mutation-proved to redden.

## What is NOT measured here, and is owed

- **A Studio MicroProfiler capture** of the paint arm. The lab pass exists and reports
  the arm; nobody has taken the capture. That is the `the-solver-already-told-you`
  pattern and it is named rather than papered over.
- **A physical device run.** `PENDING_PHYSICAL`.
- **The `CanvasGroup` cost per faded node.** An authored `opacity` materializes a real
  `CanvasGroup` with its own render buffer, and a render buffer is a GPU-side cost the
  Lune target cannot have. The lab arm now mounts real fade groups so a Studio capture
  will see it; headless cannot, and this file does not pretend otherwise.
