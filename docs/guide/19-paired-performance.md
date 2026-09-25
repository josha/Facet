# Paired performance comparison

This page compares the headless controlled scenes and the microbenchmarks of
`main` and of the candidate branch on one host. The runs are paired and
interleaved. Read the ratios. Do not read the absolute numbers as budgets or as
device timings.

| Label | Commit | Description |
|---|---|---|
| base | `a8c8895673c0745506908b66dc89f8cead6b66f3` | `main` before the native cutover |
| cand | `6789e3b1` | `codex/compose-ui-simplification` (draft PR josha/Facet#22) |
| tok | `5530b29f` | `cand` plus the StyleSheet token prototype, on branch `perf/stylesheet-tokens` |

`cand` includes the three optimizations that
[Earlier results](#earlier-results) describes. It also includes a change to the
headless engine double: the double caches its datatype check for each class and
property.

## Host

- CPU: `Apple M2 Max`, 12 cores (`sysctl machdep.cpu.brand_string hw.ncpu`).
- Memory: 32 GB.
- OS: macOS 27.0, build 26A428. Lune 0.10.4 and StyLua 2.5.2, from
  `rokit.toml`.
- The host is a shared developer workstation. It is not an isolated virtual
  machine. Several Roblox Studio instances and the processes of other agents ran
  during all measurements. The 1-minute load average was 14.7-47.5 during
  the main run and 14.9-19.0 during the token run. The yardstick columns
  show the effect. Interleaving and pairing decrease the effect of the load on
  the ratios. They do not remove it. The spread columns show single rounds that
  are more than 10 times slower than the median.
- `bench/perf_budgets.json` was recorded on a different Apple-silicon Mac.
  Budget pass or fail on this host is not evidence. This page does not use the
  budgets.

## Method

1. Each commit has its own git worktree.
2. Each round runs `base`, then `cand`. The token run also runs `tok`. The main
   run has 8 rounds.
3. In each round, each of the 27 controlled scenes runs in a new Lune process:
   `lune run tools/lune/perf_paired_scene <scene>`. The runner calls the
   unmodified `perf_runner.runScene` of the commit, with the scene, warm-up and
   sample counts of the commit, at the reference profile (`floorAndroid`).
   `main` cannot run its full `tools/perf.sh` matrix, because three scenes fail
   setup. A new process for each scene isolates that failure. All commits use
   the same method.
4. After the scenes, the round runs the `tools/bench.sh` of the commit.
5. `tools/perf_paired.py report` calculates these values:
   - `p50` and `p95`: the median over the rounds of the p50 and p95 of each run,
     in ms.
   - `ratio`: the median of the second commit divided by the median of the first
     commit. A ratio less than 1 shows that the second commit is faster.
   - `paired range`: the minimum and the maximum of the ratio of the two runs in
     the same round.
   - `spread`: the minimum and the maximum p95 over the rounds.
   - `Flag`: the ratio is more than 1.05, and each paired ratio is more than 1.
     Thus the second commit is more than 5% slower, in the same direction, in
     each round.

The two commits use the same scene names. `bench/workload_fidelity.json` on the
candidate records how each native workload keeps the population, the trigger and
the cadence of the original scene. The headless candidate numbers do not include
native engine layout, text measurement, selection routing, StyleSheet
resolution, asset loading or paint. The baseline numbers include the Facet solver
and renderer that the candidate removed. Thus a ratio compares the Luau work of
each commit. It is not a frame-time comparison.

### Unavailable baseline scenes

`alert-present-dismiss`, `picker-menu-open-close` and `radial-menu-open-close`
fail setup on `main` in each round, with the error
`Compose[owner/no-active-owner]: cleanup has no owner to register with`. These
rows have no baseline number. This page does not estimate one.

## Summary for 6789e3b1

| Scene | p50 ratio | p50 paired range | p95 ratio | Flag | Source of the cost |
|---|---:|---|---:|---|---|
| theme-swap-metrics | 1.453 | 1.14-1.67 | 1.251 | p50 | Facet code and engine double. Each swap retimes and writes almost all native rules. |
| theme-swap-assets | 1.445 | 1.31-2.31 | 1.244 | p50, p95 | The same as theme-swap-metrics. |
| lab-dense-scroll | 2.084 | 1.58-3.29 | 0.465 | p50 | Engine double and vendored Compose. The total work is less than on `main`. |

No microbenchmark has a flag. All other scenes have no flag. The flags that
`4afc1569` had in async-image-burst, scroll-focus-traversal, native-scroll-drag
and theme-swap-flat are gone. They came from the datatype check in the engine
double, which `6789e3b1` caches.

## base compared with cand (8 rounds)

| Scene | base p50 | cand p50 | p50 ratio | p50 paired range | base p95 | cand p95 | p95 ratio | p95 paired range | base p95 spread | cand p95 spread | Flag |
|---|---:|---:|---:|---|---:|---:|---:|---|---|---|---|
| hud-binding-storm | 0.2833 | 0.0418 | 0.148 | 0.07-0.15 | 0.8223 | 0.1307 | 0.159 | 0.02-0.37 | 0.6111-7.6178 | 0.0908-0.2272 |  |
| settings-churn | 2.9078 | 1.4609 | 0.502 | 0.32-1.15 | 5.0460 | 3.1642 | 0.627 | 0.49-3.26 | 4.4821-23.7184 | 2.3956-19.0572 |  |
| scroll-focus-traversal | 0.0796 | 0.0822 | 1.033 | 0.57-1.17 | 0.2790 | 0.3073 | 1.101 | 0.13-5.55 | 0.2175-2.0207 | 0.1705-1.2882 |  |
| collection-mutation | 1.4412 | 0.5347 | 0.371 | 0.18-0.65 | 3.2361 | 1.6984 | 0.525 | 0.16-1.73 | 2.2156-14.3864 | 1.0896-4.2898 |  |
| animation-interruption | 0.4204 | 0.0054 | 0.013 | 0.01-0.01 | 1.4793 | 0.0145 | 0.010 | 0.00-0.03 | 0.9831-6.4834 | 0.0057-0.0555 |  |
| locale-textsize-change | 0.3149 | 0.0038 | 0.012 | 0.01-0.01 | 0.9473 | 0.0059 | 0.006 | 0.00-0.06 | 0.8125-2.7964 | 0.0039-0.0503 |  |
| async-image-burst | 0.0495 | 0.0069 | 0.140 | 0.07-0.15 | 0.2036 | 0.0124 | 0.061 | 0.01-0.31 | 0.1177-0.8217 | 0.0076-0.0457 |  |
| shadow-storm | 0.0108 | 0.0001 | 0.012 | 0.01-0.01 | 0.0401 | 0.0002 | 0.005 | 0.00-0.03 | 0.0160-0.0487 | 0.0002-0.0014 |  |
| virtual-list-scroll | 1.6976 | 0.5790 | 0.341 | 0.19-0.54 | 3.7810 | 1.7601 | 0.466 | 0.10-0.79 | 2.3698-18.0921 | 1.1878-3.0596 |  |
| native-scroll-drag | 0.0062 | 0.0058 | 0.939 | 0.79-1.06 | 0.0239 | 0.0089 | 0.372 | 0.28-0.84 | 0.0088-0.0574 | 0.0069-0.0264 |  |
| dense-hud | 0.7884 | 0.0251 | 0.032 | 0.02-0.04 | 1.9734 | 0.0879 | 0.045 | 0.02-0.13 | 1.5785-6.4581 | 0.0514-0.2229 |  |
| stylesheet-state-churn | 0.1162 | 0.0263 | 0.226 | 0.18-0.24 | 0.3609 | 0.1009 | 0.279 | 0.04-0.46 | 0.2349-2.0030 | 0.0449-0.5362 |  |
| async-image-grid | 3.3048 | 1.1020 | 0.333 | 0.18-0.44 | 6.2822 | 2.7770 | 0.442 | 0.29-1.92 | 4.4141-12.5345 | 1.9994-24.0597 |  |
| screen-lifecycle-churn | 8.2138 | 4.2982 | 0.523 | 0.40-0.77 | 11.6449 | 6.9335 | 0.595 | 0.37-2.28 | 10.0590-30.4968 | 5.8914-69.5928 |  |
| theme-swap-flat | 0.2372 | 0.1113 | 0.469 | 0.21-0.54 | 0.8977 | 0.4015 | 0.447 | 0.07-0.66 | 0.6547-3.7027 | 0.2418-1.1556 |  |
| theme-swap-metrics | 0.2391 | 0.3474 | 1.453 | 1.14-1.67 | 0.8081 | 1.0108 | 1.251 | 0.86-2.56 | 0.5571-2.7700 | 0.8045-2.7273 | cand slower (p50) |
| dense-motion | 1.6630 | 0.2256 | 0.136 | 0.06-0.16 | 3.4899 | 0.6529 | 0.187 | 0.12-0.35 | 2.4789-9.7804 | 0.4612-2.2515 |  |
| control-motion | 0.1801 | 0.0255 | 0.142 | 0.10-0.15 | 1.5552 | 0.2528 | 0.163 | 0.06-0.72 | 0.9167-6.4289 | 0.0782-2.5258 |  |
| theme-swap-assets | 0.2484 | 0.3588 | 1.445 | 1.31-2.31 | 0.8996 | 1.1196 | 1.244 | 1.08-6.67 | 0.5297-3.2128 | 0.7693-21.4313 | cand slower (p50, p95) |
| lab-dense-scroll | 0.1022 | 0.2130 | 2.084 | 1.58-3.29 | 4.9625 | 2.3078 | 0.465 | 0.35-0.60 | 3.9259-10.8340 | 1.7988-5.5028 | cand slower (p50) |
| lab-collection-churn | 0.1341 | 0.1027 | 0.766 | 0.50-0.85 | 0.4473 | 0.3586 | 0.802 | 0.44-1.17 | 0.3592-1.7963 | 0.2571-0.9238 |  |
| adaptive-navigation-images | 0.3185 | 0.1087 | 0.341 | 0.18-0.39 | 1.0221 | 0.3706 | 0.363 | 0.08-1.02 | 0.5566-7.2990 | 0.3048-1.3412 |  |
| navigation-customization | 3.2498 | 0.0041 | 0.001 | 0.00-0.00 | 6.0152 | 0.0061 | 0.001 | 0.00-0.00 | 4.2310-51.2575 | 0.0052-0.0195 |  |
| alert-present-dismiss | n/a | 0.8225 | n/a | n/a | n/a | 2.1938 | n/a | n/a | n/a | 1.8307-15.4916 | base unavailable (failed) |
| picker-menu-open-close | n/a | 2.7037 | n/a | n/a | n/a | 4.7170 | n/a | n/a | n/a | 4.4277-61.9138 | base unavailable (failed) |
| picker-segmented-textsize | 0.8580 | 0.0024 | 0.003 | 0.00-0.00 | 2.2406 | 0.0026 | 0.001 | 0.00-0.00 | 1.9744-9.6094 | 0.0024-0.0290 |  |
| radial-menu-open-close | n/a | 0.0764 | n/a | n/a | n/a | 0.2437 | n/a | n/a | n/a | 0.1640-0.5108 | base unavailable (failed) |

| Microbenchmark | base p50 | cand p50 | p50 ratio | p50 paired range | base p95 | cand p95 | p95 ratio | Flag |
|---|---:|---:|---:|---|---:|---:|---:|---|
| billboard-nameplate-storm | 0.2533 | 0.0190 | 0.075 | 0.03-0.08 | 0.8340 | 0.0525 | 0.063 |  |
| collection-mutation | 0.0074 | 0.0077 | 1.048 | 0.96-1.15 | 0.0291 | 0.0229 | 0.787 |  |
| hud-binding-storm | 0.2068 | 0.1335 | 0.645 | 0.36-0.67 | 0.5954 | 0.3960 | 0.665 |  |
| motion-declarative | 5.5819 | 0.2638 | 0.047 | 0.01-0.05 | 8.2856 | 0.8196 | 0.099 |  |
| motion-explicit | 5.1626 | 0.2644 | 0.051 | 0.02-0.06 | 7.6120 | 0.8101 | 0.106 |  |
| mount-ramp | 179.4945 | 113.7075 | 0.633 | 0.30-1.32 | 202.9148 | 172.9497 | 0.852 |  |
| mount-ramp-inherited | 228.4420 | 103.1810 | 0.452 | 0.30-0.64 | 436.7787 | 157.5257 | 0.361 |  |
| mounted-slice-update-storm | 0.3190 | 0.0447 | 0.140 | 0.09-0.19 | 1.4970 | 0.1443 | 0.096 |  |
| settings-churn | 0.0093 | 0.0066 | 0.712 | 0.49-1.62 | 0.0374 | 0.0334 | 0.893 |  |
| sparse-update-under-load | 0.0012 | 0.0007 | 0.552 | 0.27-0.57 | 0.0020 | 0.0008 | 0.385 |  |
| table-mutation | 1.5047 | 0.4904 | 0.326 | 0.13-0.50 | 3.7881 | 1.6595 | 0.438 |  |
| table-resize-drag | 3.7748 | 0.8285 | 0.219 | 0.13-0.31 | 7.0585 | 2.0760 | 0.294 |  |
| textinput-typing-storm | 0.3740 | 0.0327 | 0.087 | 0.05-0.10 | 1.2158 | 0.0991 | 0.081 |  |
| zz-yardstick-cpu-after | 0.2881 | 0.2866 | 0.995 | 0.66-1.42 | 0.7218 | 0.7741 | 1.073 |  |
| zz-yardstick-cpu-before | 0.2949 | 0.2885 | 0.978 | 0.81-1.02 | 0.7767 | 0.7293 | 0.939 |  |

| Bench run | Yardstick p95 ms | Yardstick drift % |
|---|---:|---:|
| base-1 | 3.2294 | 83.9 |
| base-2 | 0.7830 | 4.1 |
| base-3 | 0.6557 | 5.3 |
| base-4 | 0.7541 | 8.6 |
| base-5 | 3.0953 | 34.0 |
| base-6 | 0.5431 | 22.8 |
| base-7 | 0.7599 | 10.0 |
| base-8 | 0.6076 | 39.6 |
| cand-1 | 1.8361 | 115.7 |
| cand-2 | 1.4652 | 116.9 |
| cand-3 | 0.7564 | 7.1 |
| cand-4 | 0.6268 | 24.0 |
| cand-5 | 0.7923 | 9.5 |
| cand-6 | 0.7824 | 32.1 |
| cand-7 | 0.7634 | 2.9 |
| cand-8 | 0.7528 | 12.3 |

## Flagged scenes

### theme-swap-metrics and theme-swap-assets

The two packages in each scene have different values of
`metrics.motion.normal`. Thus each swap changes the transition timing of each
rule that has a color or a transparency property. The count of native calls for
one swap, on `6789e3b1` with 210 rules, is:

| Scene | `SetProperties` | `SetPropertyTransitions` |
|---|---:|---:|
| theme-swap-flat | 150 | 0 |
| theme-swap-metrics | 194 | 165 |
| theme-swap-assets | 196 | 165 |

These calls are necessary with native StyleRule transitions. A StyleRule has
its own transitions, and a StyleSheet token cannot hold a `TweenInfo`. The test
"leaves unchanged native rules and running paint transitions untouched during
theme updates" also requires a `SetProperties` call when only the timing of a
rule changes.

Measured parts of the cost (`profile_scene`, 3000 steps in one process, not part
of this branch):

- The theme watch of the StyleSheet is about 70% of a step. Most of the
  remaining time is the eight skin watches.
- The engine double copies the table in each `SetProperties` and
  `SetPropertyTransitions` call. When the double does not copy, the p50 of
  theme-swap-metrics decreases from 0.295-0.299 ms to 0.234 ms (three runs of
  each). The `main` p50 in the paired run is 0.239 ms.
- These changes gave no measurable result:
  - Omit `SetProperties` when only the timing changes. The p50 changed by less
    than 4%, and one test fails.
  - Keep the result of each comparison of two transition tables. The p50 did not
    change.
  - Use StyleSheet tokens for colors. See the next section.

Thus the remaining flag is the cost of the native writes that a change of motion
duration needs, plus the table copies of the engine double. The branch does not
change the engine double, because that would change the measurement.

### lab-dense-scroll (not fixed)

The p50 ratio stays more than 2. The p95 ratio is 0.47. The work moved between
steps. The total work did not increase.

- A row is 156 px high, and a step scrolls 61 px. In 3000 steps, 1173 steps
  build a row, 1173 steps remove a row, and 654 steps (22%) change nothing. The
  p50 step removes a row. The removal costs about 0.12 ms.
- About 55% of the removal cost is the `Destroy` of the engine double
  (`tests/lib/native_engine.luau`). The remainder is owner teardown in the
  vendored Compose snapshot. The Facet watches and cleanups on this path cost
  less than 0.01 ms for each step.
- In a diagnostic harness, the mean step time of the candidate was 0.22 to 0.56
  times the mean step time of `main`.

A fix needs a change to the vendored Compose snapshot, to the engine double, or
to the workload. This branch does not change them.

## Theme swaps in Roblox Studio

The headless theme-swap scenes measure Luau work only. This check measures
frame time in the real engine, which also applies the StyleSheet.

- Host: Roblox Studio on the same Mac, a playtest at 844 x 369 points.
- Page: the gallery All controls page.
- Method: record the time of each rendered frame. Swap between the Classic
  Desktop and Glossy Touch packages 8 times, one second apart.
- Candidate (`db391974`): the gallery showcase API swaps the package. All 8 swaps
  are applied.
- `main` (`a8c88956`): the theme chips on the gallery settings screen swap the
  package. The chip grid moves after the first swap, so fewer than 8 swaps can
  apply.

| Commit | Frames | p50 | p99 | Frames over 25 ms | Worst frame |
|---|---:|---:|---:|---:|---:|
| `main` | 1111 | 16.67 ms | 19.93 ms | 1 | 29.3 ms |
| candidate | 549 | 16.66 ms | 17.54 ms | 0 | 19.8 ms |

The candidate call that swaps the package takes 2.4 ms at p50 and 3.2 ms at
p90, over 20 swaps. No swap causes a dropped frame at 60 frames per second.
Thus the headless theme-swap flag is Luau and engine-double cost. It does not
show as frame time in Studio.

## Checks of the three flags

These checks test the explanations of the three flags. They ran on
`2fdb08c7` (`cand`) against `main` (`base`). The host load average was
about 40 during the runs, so the absolute numbers are several times larger
than in the tables above. Read the ratios and the paired ranges.

### Theme swaps: the table copies of the engine double

`nocopy` is `cand` with one change in `tests/lib/native_engine.luau`:
`SetProperties` and `SetPropertyTransitions` keep the table that they get and
do not copy it. The paired run has 6 rounds and the order base, cand, nocopy
in each round (`tools/perf_paired.py run --skip-bench`).

| Scene | cand / base p50 | paired range | nocopy / base p50 | paired range | nocopy / cand p50 | paired range |
|---|---:|---|---:|---|---:|---|
| theme-swap-flat | 0.399 | 0.07-0.58 | 0.185 | 0.09-0.50 | 0.464 | 0.30-1.19 |
| theme-swap-metrics | 2.094 | 1.40-2.67 | 1.028 | 0.48-2.35 | 0.491 | 0.31-0.97 |
| theme-swap-assets | 2.660 | 1.28-8.25 | 1.203 | 0.78-4.26 | 0.452 | 0.23-0.95 |

Without the copies, the metric and asset swaps have no flag: the paired range
includes 1 in both scenes. In each round, `nocopy` is faster than `cand`.
Thus the flag comes from the table copies of the engine double. A copy does not
occur in the Roblox engine. In Roblox Studio the candidate swap has a lower
worst frame than `main` (19.8 ms against 29.3 ms, see
[Theme swaps in Roblox Studio](#theme-swaps-in-roblox-studio)). The branch
keeps the copies, because the tests read the rule tables after a write.

### lab-dense-scroll: the median and the total work

The p50 of this scene compares different step shapes. On `main` most steps
change nothing, and some steps are very slow. On `cand` more steps do a small
amount of work. The mean step time measures the total work. This run used a
script that times 600 steps after 60 warm-up steps with the `perf_scenes` entry
of each commit. It ran 5 rounds, in the order base, cand.

| Round | base mean (ms) | cand mean (ms) | cand / base |
|---|---:|---:|---:|
| 1 | 43.42 | 18.01 | 0.41 |
| 2 | 41.51 | 38.51 | 0.93 |
| 3 | 52.87 | 29.32 | 0.55 |
| 4 | 44.68 | 14.98 | 0.34 |
| 5 | 14.22 | 25.66 | 1.81 |

The median ratio is 0.55, and `cand` is faster in 4 of 5 rounds. The p50 ratio
in the paired run is 2.25 (paired range 1.47-3.90), and the p95 ratio is 0.85.
Thus the total work of `cand` is less than the total work of `main`. The two
commits use different headless hosts: `main` drives its own adapter and
presenter, and `cand` drives the native engine double. A like-for-like engine
comparison needs the performance lab place in Studio.

### The performance lab in Roblox Studio

- `cand`: the lab place ran `dense-scroll` with 2,000 rows at 388x824 and the
  Largest preferred text size, with the overlay hidden. 975 steps: p50
  2.94 ms, p95 8.45 ms. The capture row is
  `artifacts/performance-stress-places/studio/perf-dense-scroll-facet-neutral-clean-1.json`.
- `main`: the lab place does not start at `a8c88956`. Its overlay registers a
  cleanup outside a Compose owner (`Compose[owner/no-active-owner]` from
  `render/compose_controls` through `overlay.luau`). This is the same error
  that stops three `main` scenes in the headless runs. Thus a Studio A/B of the
  lab against `main` needs a change to `main`.
- Earlier `dense-scroll-native` captures in Studio measured the wrong screen.
  The cause: the `clean` and `theme` commands remounted the workload. The
  native list fills over frames and takes about 80 s in Studio with more than
  100,000 instances, so a capture after `clean` saw a list that was not full.
  Now `clean` and `theme` keep the mounted workload, and
  `native_perf_lab` tests it. The later workloads mount correctly after the
  native list.
- The branch records these Studio captures at 1280x720 and the Medium text
  size: three `dense-scroll-native` and three `dense-scroll` repeats, one
  `dense-scroll` capture with `fantasy_ornate`, and five emulator captures
  (a phone emulator in portrait and landscape, a 720p handheld, a console and a 768x1024
  handheld). The rows are in `artifacts/performance-stress-places/studio`.

No check shows a regression in the three flagged scenes.

## StyleSheet token prototype

Branch `perf/stylesheet-tokens`, commit `5530b29f`, adds this change to
`src/ui/themes.luau`:

- The sheet has one attribute for each palette role, with the name
  `FacetColor_<role>`.
- Each color rule refers to the token, for example `$FacetColor_accent`, not to a
  resolved `Color3`.
- A palette swap sets only the attributes whose color changes. A rule is
  written only when a value that is not a color changes.
- A property that refers to a color token keeps its color transition.

Result for one swap, 210 rules:

| Scene | `SetProperties` | `SetPropertyTransitions` | Token attributes |
|---|---:|---:|---:|
| theme-swap-flat | 2 (was 150) | 0 | 17 |
| theme-swap-metrics | 194 | 165 | 15 |
| theme-swap-assets | 196 | 165 | 18 |

Thus the tokens make a palette-only swap O(tokens). They do not help a swap that
also changes the motion duration, because each rule then needs new transitions.

Paired run, 8 rounds, `--skip-bench`, six style scenes:

| Scene | cand p50 | tok p50 | p50 ratio | p50 paired range | cand p95 | tok p95 | p95 ratio | p95 paired range | cand p95 spread | tok p95 spread | Flag |
|---|---:|---:|---:|---|---:|---:|---:|---|---|---|---|
| theme-swap-flat | 0.1016 | 0.0517 | 0.509 | 0.47-0.54 | 0.1980 | 0.0951 | 0.480 | 0.31-0.70 | 0.1630-0.3653 | 0.0766-0.1706 |  |
| theme-swap-metrics | 0.3128 | 0.3088 | 0.987 | 0.83-1.10 | 0.6264 | 0.6587 | 1.052 | 0.67-1.35 | 0.5082-0.9970 | 0.5860-0.7734 |  |
| theme-swap-assets | 0.3181 | 0.3167 | 0.995 | 0.96-1.02 | 0.6467 | 0.6174 | 0.955 | 0.78-1.04 | 0.5693-0.9000 | 0.5182-0.7837 |  |
| stylesheet-state-churn | 0.0242 | 0.0239 | 0.987 | 0.93-1.04 | 0.0403 | 0.0512 | 1.270 | 0.63-2.73 | 0.0263-0.0750 | 0.0288-0.1011 |  |
| shadow-storm | 0.0001 | 0.0001 | 1.000 | 1.00-1.33 | 0.0002 | 0.0002 | 1.125 | 0.80-2.75 | 0.0002-0.0002 | 0.0002-0.0005 |  |
| dense-hud | 0.0242 | 0.0241 | 0.997 | 0.95-1.05 | 0.0347 | 0.0351 | 1.010 | 0.58-1.60 | 0.0286-0.0664 | 0.0270-0.0755 |  |

| Scene | base p50 | tok p50 | p50 ratio | p50 paired range | base p95 | tok p95 | p95 ratio | p95 paired range | base p95 spread | tok p95 spread | Flag |
|---|---:|---:|---:|---|---:|---:|---:|---|---|---|---|
| theme-swap-flat | 0.1970 | 0.0517 | 0.263 | 0.24-0.28 | 0.5303 | 0.0951 | 0.179 | 0.15-0.32 | 0.3690-0.5851 | 0.0766-0.1706 |  |
| theme-swap-metrics | 0.2081 | 0.3088 | 1.484 | 1.39-1.53 | 0.5091 | 0.6587 | 1.294 | 1.04-1.59 | 0.4118-0.6205 | 0.5860-0.7734 | tok slower (p50, p95) |
| theme-swap-assets | 0.2026 | 0.3167 | 1.563 | 1.43-1.67 | 0.5042 | 0.6174 | 1.224 | 0.57-1.68 | 0.3721-1.1089 | 0.5182-0.7837 | tok slower (p50) |
| stylesheet-state-churn | 0.1066 | 0.0239 | 0.224 | 0.19-0.25 | 0.2266 | 0.0512 | 0.226 | 0.11-0.46 | 0.2131-0.4788 | 0.0288-0.1011 |  |
| shadow-storm | 0.0108 | 0.0001 | 0.012 | 0.01-0.02 | 0.0236 | 0.0002 | 0.008 | 0.00-0.02 | 0.0129-0.0383 | 0.0002-0.0005 |  |
| dense-hud | 0.5703 | 0.0241 | 0.042 | 0.04-0.04 | 1.1749 | 0.0351 | 0.030 | 0.02-0.06 | 1.0262-1.9367 | 0.0270-0.0755 |  |

Checks on the prototype: `tools/verify.sh fast` has the same result as `cand`
(suite 654 passed, one more test; the coverage producer has the same three
pending live risks). `python3 tools/check_types.py` and StyLua pass. The new
test "swaps palette colors through StyleSheet tokens without rewriting rules"
counts zero rule writes for a palette swap. The test helper that reads rule
properties now resolves `$` tokens from the sheet attributes, as the engine
does.

The prototype is not merged into this branch, for these reasons:

- It does not remove a flag.
- It changes the rule property values that a game can read. A color becomes a
  string, for example `$FacetColor_accent`.
- There is no live Studio evidence that a change of a token attribute starts
  the transition of the rule. The current documentation claims that a palette
  change animates and that Roblox retargets an interrupted change. Studio must
  show the same result for tokens before the change is acceptable.

## Earlier results

The candidate branch moved during this work: `095c0a04`, `7c1c2950`,
`4afc1569`, then `6789e3b1`. The flags and fixes on the earlier heads were:

| Scene | Flag before the fixes (p50 ratio to `main`) | Cause | Fix | Result |
|---|---|---|---|---|
| theme-swap-metrics, theme-swap-assets | 1.52-2.05 | The sheet kept only the last timing. Each swap made a new `TweenInfo`, rebuilt each transitions table and compared each property table key by key. | `Reuse rule transition tables across theme swaps` and `Remember rule property comparisons across theme swaps` | p50 ratio to the unmodified candidate 0.56-0.63 |
| scroll-focus-traversal | 1.24-1.27 | The `Enabled` binding of each `InputContext` walked the ancestors before it read the condition of the action. | `Check an action's own condition before walking its ancestry` | p50 ratio to `main` 1.00-1.03 |
| async-image-burst and others on `4afc1569` | up to 11.2 | The engine double read the class default with `pcall` on each property write. | Datatype cache in the engine double (in `6789e3b1`) | No flag |
| lab-dense-scroll | 2.08-3.30 | See above. | None | Flag stays |

The preliminary run on `095c0a04` flagged the `collection-mutation`
microbenchmark at p50 (1.103). Later runs did not confirm it (1.048-1.055).
This benchmark does not call Facet code.

## Verification on 6789e3b1

| Check | Result |
|---|---|
| `tools/verify.sh fast`, suite | 653 passed |
| `tools/verify.sh fast`, coverage producer | FAIL: 3 pending live Studio risks (the collection toolbar under phone and largest text, the shell reservation under themes and largest text, haptic motor output on physical devices) |
| `tools/verify.sh fast`, other producers | PASS |
| `python3 tools/check_types.py` | PASS |
| `stylua --check src tests tools bench examples` | PASS |

## Reproduce

```sh
rokit install
git worktree add --detach ../facet-base a8c8895673c0745506908b66dc89f8cead6b66f3
git worktree add --detach ../facet-cand 6789e3b1
python3 tools/perf_paired.py run --out /tmp/paired --rounds 8 \
  base=../facet-base cand=../facet-cand
python3 tools/perf_paired.py report /tmp/paired base cand
```

`run` copies `tools/lune/perf_paired_scene.luau` into each worktree as an
untracked file, because `main` does not have it. Close Roblox Studio and other
heavy processes before a run.
