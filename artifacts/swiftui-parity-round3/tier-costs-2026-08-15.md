# The tier record, measured (O-17) — 2026-08-15

`tests/lib/tiers.luau` records what every fast-tier exclusion costs. Both halves
of that record are typed, nothing forced them to stay true, and nothing had.

## What was measured

`lune run tools/lune/time_specs`, three runs, per-spec median. **213 spec files,
5561 cases, wall 78.9 / 79.0 / 79.9 s.** Per-spec spread across the three runs
was ~2–5 % (`overflow_sweep.spec`: 16259 / 16342 / 16496).

| spec | recorded before | measured (median) | off by |
|---|---:|---:|---:|
| `perf_lab.spec` | 16024 | **24204** | +51 % |
| `overflow_sweep.spec` | 1036 | **16342** | **+1477 %** |
| `example_drift.spec` | 4182 | **4416** | +6 % |
| `reference/sipworks_spec` | 3222 | **3961** | +23 % |
| `extension_checker.spec` | 2701 | **3795** | +40 % |
| `reference/glade_spec` | 1979 | **2471** | +25 % |
| `theme_drift.spec` | 1356 | **2037** | +50 % |
| `reference/cartwheel_spec` | 1874 | **1878** | 0 % |
| `reference/foyer_spec` | 978 | **938** | −4 % |
| `instance_recycling.spec` | 602 | **693** | +15 % |
| `reference/wardrobe_spec` | 326 | **497** | +52 % |

The ledger's own replacement numbers were stale too, exactly as O-17 warned: it
predicted ~2.5 s, then 10.0 s after the theme axis; the measured figure on the
day is **16.3 s**, and this mission's locale axis is part of why (below).

## The finding the numbers were hiding

The file's rule read *"the eleven costliest files and nothing else"*. On this
measurement that was false:

| spec | measured | in `SLOW`? |
|---|---:|---|
| `virtual_list_row_actions.spec` | 1737 | **no** |
| `row_actions_scenario.spec` | 1458 | **no** |
| `reference/foyer_spec` | 938 | yes |
| `instance_recycling.spec` | 693 | yes |
| `reference/wardrobe_spec` | 497 | yes |

Two round-3 workloads had grown costlier than three files the list excludes, and
nothing noticed — **because a rank is a claim about every file the list does not
name, and the list can only speak about itself.**

## The call: not derived, CHECKED — and the rule became a threshold

Deriving the tier from a measurement inside the suite is not possible at a
proportionate cost: the only way to know what a spec costs is to run every spec,
and the fast tier exists precisely so that does not happen between two
keystrokes. So the record stays typed and something else holds it to the run:

* `tiers.THRESHOLD_MS = 1200` — anything measured above it must be excluded or
  be a declared `FAST_ANCHOR`. Chosen at the gap in this distribution (cheapest
  above: 1458; dearest below: 938). A threshold is checkable from the outside in
  a way a rank never was.
* `tools/lune/check_tier_costs` — reads a fresh `time_specs` JSON and asserts
  (1) every exclusion was timed, (2) every recorded `ms` is within 50 % of the
  measurement, (3) nothing over the threshold sits in the fast tier undeclared.
  It is gate-tier by construction (it costs one timed suite run, ~80 s).
* `virtual_list_row_actions.spec` and `row_actions_scenario.spec` joined `SLOW`,
  which is what the rule, applied honestly, already required.

**What would catch the next drift:** the checker, wherever it is run. It is
wired into no gate row yet — the same honest rider `tools/check_source_size.py`
carries (O-29) — so today it catches drift only when somebody runs it. Wiring it
is a one-line gate edit and a round-4 row.

## Mutation evidence (all three checks bite)

| mutation | result |
|---|---|
| put the old `ms = 1036` back for `overflow_sweep.spec` | `recorded 1036 ms, measured 16496 ms (94% off)` — exit 1 |
| drop `virtual_list_row_actions.spec` from `SLOW` | `1533 ms is over tiers.THRESHOLD_MS (1200) and it is neither excluded nor a FAST_ANCHOR` — exit 1 |
| rename an exclusion (`theme_drift.spec` → `theme_drift_renamed.spec`) | two problems: the record names a spec nothing timed, AND the real spec is now over the threshold and unexcluded — exit 1 |

Unmutated: `every exclusion is timed, within tolerance, and nothing over the
threshold is in the fast tier`, exit 0.
