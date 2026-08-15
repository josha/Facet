# The lazy grid — what it costs, with the control band stated first

**Evidence class: HEADLESS LUNE.** This is a **regression signal**, not a Studio
number and emphatically not a device claim (UI-PERF-002). Lune is not the engine:
it does not create instances, does not paint, and its clock is not a frame. What
it can do honestly is say whether a change moved the framework's own work, and by
how much relative to its own noise.

Instrument: [`bench.luau`](bench.luau), run from the library root with
`lune run artifacts/lazy-grid/bench`. Order-swapped **ABBA** within every round
(A B B A), 9 rounds, medians reported.

---

## 1. The control band, stated BEFORE any delta

Four missions this week found an apparent win inside the noise, one at +13.77%
against a ±5–28% control. So the first thing this instrument measures is
**itself**: the same lazy grid mounted twice, the two arms labelled and swapped,
nothing different between them.

| | arm 1 median | arm 2 median | **A/A control spread** |
|---|---|---|---|
| mount lazy, N = 1 000 | 3.33 ms | 4.23 ms | **21.4%** |
| mount lazy, N = 10 000 | 4.93 ms | 5.14 ms | **4.1%** |

**Read every number below against 21.4%**, the wider of the two. A second run of
the whole bench reproduced 21.5% and 2.6% — the band at N = 1 000 is genuinely
that wide, because the absolute time is small enough that process noise is a
large fraction of it. Nothing here is claimed at a resolution finer than that.

## 2. Mount: lazy vs the eager `UI.Grid`

Arm B is what a consumer builds today for a grid of a collection: a `UI.Grid`
holding every cell inside a `ScrollView`. Same cell blueprint, same lane count,
same viewport, same harness.

| | N = 1 000 | N = 10 000 |
|---|---|---|
| lazy (`newVirtualGrid`) | 4.10 ms | 7.26 ms |
| eager (`UI.Grid`, every cell) | 34.22 ms | 414.08 ms |
| **ratio** | **8.4x** | **57.1x** |

Both are two to three orders of magnitude outside the control band, so the
direction is not in question. The ratio itself is not a stable quantity and is
not offered as one — it grows with N by construction, which is the point rather
than a finding.

## 3. The claim that actually matters: a scroll frame is FLAT in N

A ratio can always be made impressive by growing N. The property the construct
exists for is different and a ratio cannot state it: **the steady cost of using
the grid does not depend on how large the collection is.**

| | median | mean | max |
|---|---|---|---|
| scroll frame, N = 1 000 | 1.447 ms | 1.545 ms | 3.280 ms |
| scroll frame, N = 10 000 | 1.400 ms | 1.471 ms | 3.018 ms |
| scroll frame, N = 40 000 | 1.447 ms | 1.527 ms | 3.052 ms |

**A 3.4% spread across a 40x range of collection size** — inside the control
band, i.e. indistinguishable from measuring the same thing three times. That is
"creates items only as needed" ([SW-21]) measured rather than asserted, and it is
the number to watch for regressions: if a future change makes this row grow with
N, laziness has been lost whatever the mount ratio still says.

The build counter in `tests/virtual_grid.spec.luau` proves the same property
*deterministically* and is the real guard; this row is the continuous-valued
confirmation that nothing expensive hides behind a correct build count.

---

## What is NOT claimed, and what is owed

- **No Studio number.** Nothing here ran on the real engine, so nothing here says
  anything about instance creation, property writes or paint — and the
  MicroProfiler capture taken for the round-3 collections found `$newindex`
  (engine property writes) costing more of a frame than `arrange` does, which no
  headless instrument can see at all.
- **No device number.** No physical hardware was involved.
- **Owed: a perf-lab arm** on `examples/performance/lab/perf_lab.luau`, following
  the shape of the `variable-extents` and `table-unified` workloads added in
  `e0a0054` — its own surface so no existing capture moves, internal yields,
  workload identity written to `workspace` attributes, every verb a distribution
  rather than an n=1 headline, and `controller.stats()`'s park/refuse/recycle
  counters reported. The cost question it should answer is the one this file
  cannot: **does a band that is ONE `UI.Grid` re-measured on every window slide
  cost more or less, on the real engine, than `newVirtualList`'s N absolutely
  positioned rows?** Headlessly the two are close enough to be inside this band,
  which is precisely why it needs the engine to answer.
