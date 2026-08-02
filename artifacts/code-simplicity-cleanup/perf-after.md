# Headless performance — before vs after the Step 5.5 cleanup

> ## ✅ FIXED 2026-07-28 — the bench is now normalized, not raw wall-clock
>
> **The problem.** Every scene was compared in raw milliseconds against numbers
> frozen on one machine at one moment. That is not a stable instrument on a
> developer laptop. The SAME unchanged source measured `mounted-slice-update-storm`
> at **1.29× quiet, 1.40× mid gate-batch, and 1.54× with Roblox Studio open** —
> and the gate went red for none of those reasons. `phase-3-pilot` failed inside
> the 16-gate batch **2/2** and passed standalone **2/2**.
>
> Raising `REGRESSION_FACTOR` was rejected: it would only have traded false alarms
> for a real 2× slipping through, which is the same "proves nothing" defect class
> this stage existed to remove.
>
> **The fix — a yardstick.** `bench/scenarios.luau` gains `zz-yardstick-cpu`: a
> LuauUI-free, deterministic, allocation-free CPU workload sized to ~0.23ms (well
> above `REGRESSION_FLOOR_MS`). `tools/lune/bench.luau` measures it **before and
> after** the scenes, averages the two, divides every scene by it, and compares the
> **ratio** against the baseline instead of the milliseconds. A slow machine lifts
> both and the ratio holds still. The before/after pair also yields a **drift**
> number: how much the machine moved *during* the run.
>
> **Verification — all four measured, not asserted:**
>
> | Test | Result |
> |---|---|
> | Quiet, against the re-frozen baseline | every gated scene **0.97–1.06×**. Was 1.08–1.29× under the old raw rule |
> | Under 20 spinners on 14 cores (load 11.5) | **1** marginal false trip (1.55×) instead of **3**; spread 3.33 → 1.29. `table-resize-drag` went 4.2× raw → 1.55× normalized |
> | A **real** injected 2× slowdown (scene body run twice), quiet | **CAUGHT** — `vs-base=2.10x REGRESSION`, bench FAIL. The fix does not blunt real detection |
> | Divisor choice | an allocation-heavy yardstick was trialled and **rejected**: it tracked the median gated scene's load-response to 11%, the pure-CPU one to **3%** |
>
> **Baseline re-frozen** from the **median of 3 quiet runs** (not one sample), storing
> `p95_norm` as the gated value with `p95_ms` kept as descriptive only. Before
> re-freezing, the drift since 2026-07-25 was checked for the thing that would have
> made a re-freeze dishonest: the 4 gated scenes had all moved **together**
> (1.08–1.29×, median 1.18×) with no single outlier, which is an environment shift,
> not a code regression. A re-freeze that buried a real regression is exactly what
> was being guarded against.
>
> **Honest limits — this reduces load sensitivity, it does not eliminate it.**
> Scene-level load response is itself wildly variable (measured 0.49×–3.66× across
> scenes in one loaded run, and the median moved between two nominally identical
> load experiments). No single scalar divisor can cancel that. So:
>
> - A run where the yardstick drifts **>15%** now prints a loud **UNTRUSTWORTHY RUN**
>   warning naming Studio and concurrent gate batches as the usual causes.
> - That warning deliberately **does not suppress the failure**. Suppressing on high
>   drift would hand anyone a way to launder a real regression by running the bench
>   on a busy machine.
> - **Still do not run `tools/bench.sh`, or a gate that invokes it, with Studio open.**
>   `tools/prior_gates.sh` settles on load average before each gate for the same reason.

**Evidence class:** headless regression screening only (`lune-headless (trend
screening only; device authoritative per design §14.3)`). This is **not** a
device-performance claim and never becomes one.

- **Before:** `artifacts/code-simplicity-cleanup/baseline/bench-before.{txt,json}`,
  captured at the frozen baseline before any source edit.
- **After:** `artifacts/bench.json`, regenerated at the FINAL cleanup source by
  the `expansion-textinput` gate's own `expansion-adr-bench-rollback` check during
  the prior-gate rerun (that check runs `tools/bench.sh` and then asserts the
  scene is present), so the after-numbers come out of a gate rather than a
  hand-run.
- The bench's own verdict at the final source: `"status": "PASS"`, and
  `"regression": false` on **every one of the 17 scenes** against its
  `regressionFactorP95: 1.5` rule.

## p50 (ms), all 17 scenes

| Scene | Before | After | Δ |
|---|---:|---:|---:|
| billboard-nameplate-storm | 0.0530 | 0.0512 | −3.4 % |
| collection-mutation-custom | 0.0050 | 0.0049 | −2.5 % |
| collection-mutation-fusion | 0.0060 | 0.0058 | −2.8 % |
| collection-mutation-imperative | 0.0047 | 0.0047 | ±0 % |
| hud-binding-storm-custom | 0.1677 | 0.1591 | −5.1 % |
| hud-binding-storm-fusion | 0.3199 | 0.2970 | −7.2 % |
| hud-binding-storm-imperative | 0.0473 | 0.0430 | −9.1 % |
| mounted-slice-update-storm | 0.0871 | 0.0830 | −4.7 % |
| settings-churn-custom | 0.0050 | 0.0050 | ±0 % |
| settings-churn-fusion | 0.0139 | 0.0125 | −9.7 % |
| settings-churn-imperative | 0.0125 | 0.0104 | −16.7 % |
| sparse-update-under-load-custom | 0.00100 | 0.00096 | −4.2 % |
| sparse-update-under-load-fusion | 0.0022 | 0.0021 | −5.0 % |
| sparse-update-under-load-imperative | 0.0174 | 0.0172 | −1.2 % |
| table-mutation | 0.6631 | 0.6122 | −7.7 % |
| table-resize-drag | 5.6626 | 5.4420 | −3.9 % |
| textinput-typing-storm | 0.0681 | 0.0655 | −3.8 % |

**No scene regressed.** Every scene is the same or faster.

## Reading it honestly

A single unpinned bench run on a laptop is noisy, and a uniform few-percent
improvement across seventeen unrelated scenes is at least partly run-to-run
variance — it must not be reported as "the cleanup made LuauUI 5 % faster".

What it *does* support is the only claim this row has to make: **nothing got
slower**, which is what a behaviour-preserving pass owes. Two of the landed
changes have a mechanism that points the same way and would show up exactly here:

- **C-02** removed a closure that was allocated *per changed prop per frame* inside
  `controller.refresh`'s dirty loop. `hud-binding-storm-*` is the scene that drives
  many prop changes per frame, and it is the largest mover on all three cores
  (−5.1 %, −7.2 %, −9.1 %).
- **C-03** removed a full mounted-tree walk from every `scrollToVisible` call, which
  fires on every focus move.

Neither is large enough to prove from this data alone; both are consistent with it.
