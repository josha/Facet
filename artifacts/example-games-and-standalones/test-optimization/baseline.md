# Verification baseline — measured before anything was changed

Stage `example-games-and-standalones`, row **TEST-1**. Every number here was taken
from a tool in this run; nothing is carried over from the older planning document,
because `tools/test.sh`'s transcript cache landed after that document was written and a
percentage taken against those numbers would flatter the result.

## The machine

| | |
|---|---|
| Model | Mac16,11 (Apple silicon), 14 cores, 64 GB |
| macOS | Darwin 25.6.0 |
| Lune | 0.10.4 |
| Rojo | 7.7.0 (rokit-managed) |
| StyLua | 2.5.2 |
| Python | 3.14.4 |
| Tree | `7bcc30a`, clean under `src/ tests/ examples/ vendor/` |
| Other load | Roblox Studio open with the showcase place (2.8 GB), `studio_sync` serving on :8642 |

The cold suite and fast tier were measured alone. Runs taken while another
measurement was in flight are marked **contended** and are not used for any
before/after claim.

## The headline

| Run | Wall | User CPU | Peak RSS | Result |
|---|---:|---:|---:|---|
| **Full suite, cold** (`./run-tests.sh`) | **1587.03 s** (26 m 27 s) | 1564.27 s | **14.25 GB** | 7678 passed, green |
| **Fast tier** (`./run-tests.sh --fast`) | **273.22 s** (4 m 33 s) | 268.95 s | 7.38 GB | 6988 passed, green |
| Every spec run **alone**, summed | **195.0 s** | — | 25–54 MB typical, 2.48 GB worst | 300 specs, 7388 passes |

`tools/test.sh`'s own header records the measurement the cache was built against:
**83.4 s a run, 5618 passed**, 2026-08-16. The suite is now 36 % larger in cases and
**19 times slower in wall clock**.

The third row is the one that reframes the problem. **The specs are not slow.** Run
one at a time they cost 0.01–0.3 s each and hold tens of megabytes; the whole set sums
to a little over three minutes. Put them in one process and the same work takes
twenty-six minutes and 14 GB.

*(Caveat, recorded rather than smoothed over: five reference specs live at
`tests/reference/<name>_spec.luau` and `run_one` cannot address them, so their cost —
on the order of ten to fifteen seconds — is missing from the 195 s. The comparison
survives it.)*

## Where the time actually goes

The dearest specs **in isolation**, which is the only measurement that attributes
honestly here — an in-process ranking charges the collector's work to whichever spec
happens to allocate next, which is exactly why the previous ranking blamed whatever
ran last and found nothing:

| Spec | Alone | Peak RSS |
|---|---:|---:|
| `theme_drift` | 42.8 s | 47 MB |
| `perf_lab` | 28.0 s | 619 MB |
| `overflow_sweep` | 25.1 s | 2482 MB |
| `extension_checker` | 7.5 s | 71 MB |
| `example_drift` | 4.5 s | 39 MB |
| `examples_gallery` | 3.1 s | 259 MB |
| `virtual_list_row_actions` | 2.2 s | 174 MB |
| `row_actions_scenario` | 1.8 s | 69 MB |
| `gallery_chrome` | 1.7 s | 403 MB |
| `mount_unmount_soak` | 1.2 s | 177 MB |

Three specs are half the isolated total. `theme_drift`, `example_drift` and
`extension_checker` are all the same shape — a whole-tree source scan re-run once per
case — which is a named target in the binding plan ("whole-tree scans repeated per
case").

Full table: `perspec-head.tsv`.

## Why one process costs eight times the sum of its parts

Measured directly, with a throwaway probe rather than inferred from the ranking. Luau
implements only `collectgarbage("count")` — there is no way to force a collection — so
a series that keeps climbing across laps is retention, not a collection nobody asked
for. Each row is the heap in MB after each additional 50 laps:

```
core only                              3.2 →   3   3   3   3   4   4     flat
core + environment                     3.9 →   3   6   5   4   4   6     flat
core + env + adapter + presenter       6.2 →   5   6   3   5   6   3     flat
blueprint construction only          194.9 → 195 196 197 197 198 198     flat

present(20 buttons) + presenter.dismiss(handle)    3.3 →  12  24  34  41  42  61
present(20 buttons) + handle.dismiss()            61.9 →  57  76  94  86 104 123
present(20 buttons), never dismissed             123.6 → 142 161 139 158 176 195
same screen id every lap                           3.3 →  11  23  20  40  42  39
unique screen id every lap                        39.6 →  59  52  71  91  72  91
same id, 200 buttons instead of 20                94.6 → 185 247 304 316 460 427
```

**Presenting a screen retains roughly 5.5 KB per presented node, and the documented
teardown recovers about a fifth of it.** Constructing a core, an environment, an
action system, an adapter, a presenter, or a blueprint retains nothing measurable. It
is not a path-keyed cache — reusing the same node ids still leaks. Retention scales
with the number of nodes presented, which is the strongest clue and the last row's
whole point.

The suite performs many thousands of present/dismiss cycles in one process. At that
rate the heap reaches 14 GB, and from there the collector's marking cost dominates
every remaining case. That is the twenty-six minutes.

This is a **framework defect, not a test defect**. The same retention accumulates in a
real game session; the suite is simply the first place it grew large enough to be
impossible to ignore.

## What the sweep costs on top of that

From the producer census over all 31 registered stages, 504 check rows (487 with a
command, 17 honest literal device-or-human rows):

- **The suite is already solved.** 228 rows call `tools/suite_transcript.sh` and 33
  call `tools/test.sh` directly — 261 trigger points. Without the cache that is 261
  full runs; with it, one run per tree state. That fix landed 2026-08-16 and holds.
- **The static-analysis battery never got the same treatment**, and it is now the
  repeated work. In one full sweep, with byte-identical arguments each time:
  `check_registration_cli` ×26, `check_docs_cli` ×22, `check_boundary` ×14,
  `check_manifest_integrity.py` ×12, `check_prop_parity_cli` ×12, `stylua --check` ×11
  (753 files each time), `check_surface_ledger` ×11, `check_example_drift_cli` ×8,
  `bench.sh` ×8. From `api-architecture-consistency` onward most stages carry one row
  chaining the same nine-producer battery verbatim.
- **The settle wait** in `prior_gates.sh` idles up to 45 s before *every* gate waiting
  for the load average to fall — up to 23 minutes across 31 gates — although only a
  handful of gates measure anything timing-sensitive.
- **This stage is the first to sweep all 31 priors.** The largest sweep before it was
  `swiftui-parity-round4` at 28.

Deliberately **not** cacheable, recorded so a later pass does not "optimize" one by
mistake: `check_flat_baseline` (its neutral dump is regenerated and compared, never
read from store — caching a baseline is the exact anti-pattern the gate-integrity work
removed), and `bench.sh` / `perf.sh` / `soak.sh` / `faults.sh` / `fuzz.sh`, which
measure time, memory and randomness. A cached timing is not a timing.

## Two things found while measuring, worth recording

**Two of the three transcripts in `artifacts/suite_cache/` are truncated** — 8375 and
10920 lines with no `N passed` summary against a complete run's 11449. `tools/test.sh`
refuses both, correctly, so nothing false was ever served. But a suite that sometimes
dies partway is a suite that can cost twenty-six minutes and return nothing.

**A streaming prototype was measured and is not the fix.** Running each spec's cases as
soon as it finished declaring them — so its fixtures could be released before the next
spec was read — was the obvious first hypothesis, and it is wrong: contended, the run
reached the same point roughly 25 % faster and still climbed past 12 GB. The retention
is not the registered case closures. That measurement is why the effort went to the
leak instead of to the harness, and it is kept here so the next person does not spend
the same hour. (`suite-streamed.txt` / `.time`, contended, killed at 522 s.)

## Rascal Rally, for comparison

| Run | Wall | Peak RSS | Result |
|---|---:|---:|---|
| Full suite, cold (`./run-tests.sh`) — **contended** | 152.73 s | 1.07 GB | 3538 passed, green |
| Every spec run alone, summed | 55.7 s | 215 MB worst | 219 specs, 3406 passes |

Two things this settles.

**Rascal Rally is not in trouble.** Two and a half minutes and a gigabyte is an
ordinary suite, and this number was taken with three agents working on the machine, so
it is pessimistic.

**The same shape is there, one third the size.** Its one-process run costs 2.7× the sum
of its isolated parts, against Facet's 8×. That is what the retention predicts:
Rascal Rally's specs mount far fewer screens than Facet's do, so the same per-screen
leak buys a gigabyte instead of fourteen. It is corroboration, not a second defect.

Its dearest specs alone: `facet_large_text_sweep` 8.2 s, `sponsor_influence` 6.5 s,
`facet_sponsor_table` 4.7 s, `facet_sponsor_cards` 4.6 s, `facet_sponsor_story` 4.0 s
— the Sponsor presenter build-out, which is also where its Facet integration lives.
Full table: `perspec-rascalrally.tsv`.

## Still owed at this row

- Rascal Rally cold/warm on a **quiet** machine, and its fast/affected tiers — it has
  a transcript cache mirroring Facet's but **no fast tier and no affected loop**, and
  no timing was recorded anywhere in that repository before this measurement.
- Per-producer timings for the static-analysis battery.
- One timed attempt at this stage's gate and its prior-requirement path.

Those are measured after the leak is fixed, because every one of them is currently
dominated by a suite run that is about to change by an order of magnitude.

## Two gate producers were already red at HEAD

Found while timing the producers, and both pre-date this stage. Recorded here
because "the prior gates pass" is one of this stage's own exit conditions, and it
was not true when the stage opened.

**`stylua --check src tests tools bench examples` — FAIL, five files.**
`tests/scroll_indicators.spec.luau`, `tests/paint_extensions.spec.luau`,
`tests/scroll_window_clip.spec.luau`, `tests/theme_layer_application.spec.luau`,
`tools/lune/_probe_containment_cost.luau`. Around eleven gate rows across eleven
stages invoke it. Fixed by formatting them; all four affected specs re-run green
(12, 50, 8 and 58 passed).

**`lune run tools/lune/check_boundary` — FAIL, three violations.** Around
fourteen rows across thirteen stages invoke it.

```
examples/gallery/scenarios/adaptive_controls.luau  -> Facet.tokens.chrome_slots
examples/gallery/scenarios/nested_compositing.luau -> Facet.layout.transform_footprint
examples/reference/p4_foyer/init.luau              -> Facet.tokens.chrome_slots
```

Bisected against `tools/lune/check_boundary` at six commits: PASS at `22fc4cd`,
`1318a69`, `43e6add`, `1139c04`, `1656fd7` and `070fa9d`; FAIL from **`59e0c1d`**
(2026-08-29, "Fix the 'All controls' empty-mount defect"). That commit fixed a
genuine Studio module-resolution defect by moving three examples from a relative
`require("../../../src/…")` to an engine-instance
`require(game.ReplicatedStorage.Facet.<area>.<module>)`. The reach was always a
boundary violation; the new spelling is simply the one the checker can see. The
checker is right and the commit was reviewed without running it.

Neither of these needs a framework change. `Facet.layout.transformFootprint` is
already a public export — `nested_compositing.luau`'s own comment says so and the
file kept its resolver anyway — and `chromeInsets` is documented public
theme-snapshot data (`docs/reference/api.md` §6336-6360, which names this exact
use: "read directly only when a caller must predict a decorated node's content
box"). Both are example-only fixes.

**The finding underneath both:** a gate row that nobody runs between missions is a
gate row that reports the state of the last mission that ran it. The optimization
half of this stage exists so that running them is cheap enough to be routine.
