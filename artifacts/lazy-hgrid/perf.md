# `LazyHGrid` — headless perf, with the control band first

**Evidence class: HEADLESS LUNE — REGRESSION SIGNAL ONLY (UI-PERF-002).** Lune is
not the engine. Nothing here is a device claim, a Studio number, or a frame budget.

Instrument: `artifacts/lazy-hgrid/bench.luau` — the arm-for-arm twin of
`artifacts/lazy-grid/bench.luau`, so the two axes are comparable rather than each
merely plausible.

```
cd GameStudio/ui/LuauUI && lune run artifacts/lazy-hgrid/bench
```

Three runs, 2026-08-15. `REPS = 9`, every pair order-swapped ABBA (A1 A2 A2 A1)
so linear drift cancels, medians reported.

## 1. The A/A control, stated before any delta

Both arms mount the **same** horizontal lazy grid. Nothing differs, so the spread
is pure instrument noise and it is the floor under every number below.

| N | run 1 | run 2 | run 3 | widest |
|---|---|---|---|---|
| 1 000 | 3.33% | 2.18% | 1.88% | **3.33%** |
| 10 000 | 5.66% | 10.52% | 2.44% | **10.52%** |

**A delta smaller than ~10.5% is not a result on this instrument.**

## 2. Mount: lazy vs eager

Arm B is what a consumer builds without this control — a sideways `UI.ScrollView`
over a plain `UI.Grid { flow = "column" }` holding every cell.

| N | lazy (median) | eager (median) | ratio |
|---|---|---|---|
| 1 000 | 3.85 – 4.34 ms | 41.1 – 42.1 ms | **9.5 – 10.7x** |
| 10 000 | 8.56 – 10.50 ms | 493 – 587 ms | **51.2 – 57.7x** |

Tiering: at N = 10 000 the ratio is ~50x against a ≤10.5% control band — three
orders of magnitude clear of the noise floor, and it is a *structural* difference
(28 cells built versus 10 000), not a micro-optimisation. At N = 1 000 the ratio
is ~10x, also far outside the band. The run-to-run spread of the ratio itself
(51.2 → 57.7) is larger than the control band and should **not** be read as
meaningful: only the order of magnitude is.

## 3. The laziness claim itself: a scroll frame is flat in N

40 driven scroll frames per world, `driveScroll` + `refresh`.

| N | run 1 median | run 2 | run 3 |
|---|---|---|---|
| 1 000 | 2.448 | 2.583 | 2.764 |
| 10 000 | 1.710 | 2.527 | 1.740 |
| 40 000 | 1.768 | 1.700 | 1.722 |

**Read this honestly.** The across-N spread (1.70 – 2.76 ms over a 40x range of N)
is *the same size as the run-to-run spread at a fixed N* — 1.710 / 2.527 / 1.740 at
N = 10 000 alone is a 32% band. So the claim this table supports is **"no trend in
N"**, not "identical in N": a 40x collection is not measurably slower per frame,
and the residual variation is the instrument. The N = 1 000 rows carry a `max` of
~152 ms in runs 1 and 3 and ~4 ms in run 2 — a first-world warm-up outlier that
moves the *mean* and not the median, which is why medians are the column.

The structural claim behind it is not measured here at all, it is *counted*, and
it is two-sided: `tests/virtual_hgrid.spec.luau` pins **exactly 28** cells built on
10 000 items and **28 on 40** — an exact count fails "mount nothing" as hard as
"mount everything", and the differential across collection sizes is what says the
work does not grow with the data.

## 4. Regression check: the vertical grid after the solver refactor

The column-major work rewrote the flow grid's measure and arrange to share one
plan. `artifacts/lazy-grid/bench.luau`, re-run unchanged on the same machine:

| | recorded before (perf.md, 2026-08-15) | after |
|---|---|---|
| A/A control | 21.4% / 4.1%, then 21.5% / 2.6% | 12.1% / 5.7% |
| mount N=1 000 | 8.4x | 8.9x |
| mount N=10 000 | 54.2x / 57.1x | 60.2x |
| scroll frame | 1.447 / 1.400 / 1.447 ms | 1.684 / 1.627 / 1.583 ms |

Every number is inside or better than its own control band. Nothing regressed;
nothing here is claimed as an improvement either.
