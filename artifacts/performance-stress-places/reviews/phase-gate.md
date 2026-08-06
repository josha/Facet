# Fresh-context phase-gate review — `performance-stress-places` (roadmap Step 9)

**Reviewer:** independent fresh-context phase-gate verifier (Opus 5).
**Date:** 2026-08-04. **Verdict: FINDINGS — the gate does not pass at the reviewed source.**

Everything below was rerun or read by this reviewer. No claim here rests on the
implementer's summary. Source was mutated only in a temporary, restored form for
falsification; the tree was returned to its reviewed state (verified file by file).

---

## 1. Verdict

**FINDINGS.** `tools/gate.sh performance-stress-places` exits **1** with status
**`FAIL_RECOVERABLE`**: 19 of 22 checks PASS, three are red. Two of the three are
genuine missing evidence, not bookkeeping.

The stage's honesty controls are, on the other hand, real. I tried to break eight
of them and all but one bit. No device claim is laundered anywhere: `phone-physical`
stays `measured: false`, `tools/perf.sh` skips all three device budgets by name, the
ledger contains no `PASS_PHYSICAL` cell, and the capture checker refuses a relabelled
Studio row. The `PL-1` / `PL-P3` split is honest, not evasive (§5).

---

## 2. Gate criteria checked

| # | Criterion | Command run | Observed |
|---|---|---|---|
| G1 | Gate green | `tools/gate.sh performance-stress-places` | **exit 1**, `FAIL_RECOVERABLE`; red: `rascalrally-consumer`, `prior-gates-unregressed`, `fresh-context-reviews` |
| G2 | Full suite | `./run-tests.sh` | exit 0. Under my 2-line solver mutation: `2 failed, 3364 passed` → **3366 total**, consistent with the pinned floor `tools/test.sh 3366` |
| G3 | Headless perf gate | `tools/perf.sh` | **PASS**, 100 runs / 20 scenes. `lab-dense-scroll` p95 4.02 vs trend 15.14 / ceil 8.33; `lab-collection-churn` 2.55 vs 10.41 / 8.33 |
| G4 | Device budgets not satisfied from host rows | `tools/perf.sh` output + `bench/perf_budgets.json` diff | All three device budgets printed as *"budget declared but not yet measured on that hardware (PENDING_PHYSICAL)"*. `deviceBudgets` block **unchanged** vs `HEAD`; `phone-physical.measured` still `false` |
| G5 | Place doctor | `python3 tools/check_perf_place.py` | **PASS** exit 0 — 16 required instances, 5 version markers, publish-safe |
| G6 | Capture admissibility | `python3 tools/check_perf_captures.py` | **PASS** exit 0 — 6 rows, `{'studio': 6}`, **0 device rows** |
| G7 | Manifest integrity | `python3 tools/check_manifest_integrity.py` | **PASS** — 546 suite greps, all anchored to the pass marker |
| G8 | Perf-gate falsifiability (PL-15) | `LUAUUI_PERF_INJECT_REGRESSION=lab-dense-scroll LUAUUI_PERF_INJECT_FACTOR=8 tools/perf.sh` | **FAIL** as designed: `lab-dense-scroll 32.11 OVER-TREND`, 2 violations (trend + frame-ceiling) |
| G9 | Injected artifact refused as baseline | `python3 tools/check_perf_metrics.py` | On injected artifact **exit 1** (`carries an injectedRegression stamp`); on the restored artifact exit 0 |
| G10 | Baseline tool scope isolation | `lune run tools/lune/perf_baseline_scene lab-dense-scroll` + JSON diff | **True** — only `lab-dense-scroll` changed; every other scene byte-identical in that run |
| G11 | Consumer suite live (PL-19 half) | `games/RascalRally/code/./run-tests.sh` | **3089 passed**, exit 0 |
| G12 | Place build determinism | `rojo build` ×2 + `cmp` | **Deterministic**; the checked-in `LuauUI-PerformanceLab.rbxl` (1 355 534 B) is byte-identical to a fresh build of current source — the artifact is current, not stale |

### The three red checks

- **`prior-gates-unregressed`** — `python3 tools/check_perf_gate_evidence.py prior-gates`
  fails with `FileNotFoundError`. **Neither `artifacts/performance-stress-places/prior-gates.txt`
  nor `prior-gates-supplement.md` exists.** PL-20's prior-gate sweep has not been run
  at the final source. This is missing evidence, not a wording problem.
- **`fresh-context-reviews`** — `reviews/` contains only `README.md` and
  `roblox-platform.md`. `architecture.md`, `reactive-runtime.md` and `phase-gate.md`
  are absent, yet `reviews/README.md` lines 9–11 present all four as delivered and
  link to them. See F-4.
- **`rascalrally-consumer`** — `consumer-impact.md` exists and the game suite is green
  (I ran it: 3089), but the ledger does not contain the literal string `was NOT re-run`
  the `run` greps for. Substantively minor; the check is correct to be red until the
  ledger states the canary limitation it is pinned on.

---

## 3. Artifact audit (claimed vs found)

| Claimed | Found | Note |
|---|---|---|
| `studio/perf-lab.json` | present, 11 KB | preflight, scopes, native ref, theme legs, large text, async, soak, fault, teardown, capture row |
| `studio/device-matrix.json` | present | `evidenceClass: "emulator"`, explicit boundary naming `EMULATION` and `PENDING_PHYSICAL`; five rows, no timing numbers |
| `studio/pl9-capture-set.json` | present, 6 rows | 3 LuauUI + 3 native repeats, one workload identity, `datasetDigest c8b21690` |
| `studio/pl13-dense-scroll-overlay.png` | present, 1.5 MB | referenced by `perf-lab.json.captures`; existence asserted by the gate's `studio` section |
| `optimization-log.md`, `decisions.md` | present | PLN-1..PLN-8; L-1..L-4, N-1, N-2 |
| `place.json`, `captures.json`, `prove-perf-gate.json` | present | all regenerate identically on rerun |
| `acceptance.md` | present | PL-1..PL-21 `PASS_AUTOMATED`; PL-P1/PL-P2 `PENDING_PHYSICAL`; PL-P3 `PENDING_HUMAN`; **no `PASS_PHYSICAL` cell anywhere** |
| `review-packet.md`, `consumer-impact.md` | present | |
| **`prior-gates.txt`** | **ABSENT** | PL-20 |
| **`prior-gates-supplement.md`** | **ABSENT** | PL-20 |
| **`reviews/architecture.md`** | **ABSENT** | linked by `reviews/README.md` |
| **`reviews/reactive-runtime.md`** | **ABSENT** | linked by `reviews/README.md` |
| `artifacts/phase-4/perf.json`, `bench/perf_budgets.json`, `artifacts/test.json` | present | perf artifact clean (no `injectedRegression` stamp) |

---

## 4. Falsification results — which checks can actually fail

Every mutation below was applied, observed, and reverted.

| ID | Mutation | Expected | Observed | Bites? |
|---|---|---|---|---|
| M1 | `dataset.VERSION = "perf-dataset/` → `"MUTANT/` | place doctor red | `FAIL — does not carry the version marker` exit 1 | **yes** |
| M2 | rename `lab/rows.luau` → `rowsX.luau` | place doctor red | `FAIL — the built place has no .../rows` exit 1 | **yes** |
| M3 | append `-- MUTANT` to `examples/gallery/scenarios/runner.luau` | runner-identity red | **PASS exit 0** | **no** — see F-6 |
| M4 | repoint project at a *diverged* copy of the runner | runner-identity red | `FAIL — not byte-identical` exit 1 | yes |
| M5 | repoint project at a *byte-identical* copy | (fork detection) | PASS exit 0 | no (by design) |
| C1 | delete `graphicsQualityLevel` from a capture row | capture check red | `FAIL — missing or unrecorded` exit 1 | **yes** |
| C2 | relabel a `studio` row as `phone-physical` | capture check red | `FAIL` ×5 incl. *"a phone-physical row carries studioVersion …; a retail client has none"* | **yes** |
| C3 | flip a ledger cell to `PASS_PHYSICAL` | capture check red | `FAIL — a device claim needs a device row` | **yes** |
| C4a | `thermalNote = "unknown"` | red | `FAIL` exit 1 | yes |
| C4b | `thermalNote = "unknown/unrecorded"` | red | **PASS exit 0** | **no** — see F-7 |
| E1 | `device-matrix.json evidenceClass` → `"studio"` | evidence check red | `FAIL — these rows are emulation and must say so` | **yes** |
| E2 | append the truthful ninth timer `LuauUI/reset` | should stay green | **`FAIL — 9`** | **inverted** — see F-2 |
| S1 | delete the memo's `ctx.compact` **and** `ctx.textFacts` replay lines in `src/layout/solver.luau` | `measure_memo.spec` red | `2 failed, 3364 passed` — `seed 612` (compact) and `seed 91` (truncated) both red | **yes** |
| S2 | (same mutation) `seed 132` case | expected red | stayed green | **no** — see F-8 |

`tools/lune/gate_manifest.luau` for this gate now carries a real `run` on every one of
the 22 checks, and `check_manifest_integrity.py` confirms all suite greps are anchored
to the pass marker. I found no check in the "cannot ever fail" class except the two
weak ones recorded as F-6 and F-8.

---

## 5. Is the PL-1 / PL-P3 split honest?

**Yes.** I checked this specifically because a stage that invents a new pending row at
close is exactly where an easy row gets to pass a hard one.

The evidence is unambiguous: all six PL-9 capture rows carry
`placeName: "injected-Place1"`, and `perf-lab.json.preflight.stampNote` says *"one stamp
per inject … re-injected and re-played after every source change"*. The emitted `.rbxl`
was demonstrably **never opened**. The original PL-1 demanded `E0 build + E3 open-and-run`
with a `studio/preflight.json` that does not exist.

PL-1 as now worded claims exactly `E0 build + E1 tree inspection` and cites
`place.json` — which is precisely what `check_perf_place.py` proves, and which I
independently mutation-tested (M1, M2). PL-P3 carries the boot as `PENDING_HUMAN` with
its own row, and `physical-rows` greps for it. `decisions.md` PLN-7 states the gap in
plain words ("none of them was `File → Open from File`"). This is the execution
contract's rule applied correctly, not evaded.

One residual: PL-13 remains `PASS_AUTOMATED` for a preflight whose canonical artifact
name in the original ledger (`studio/preflight.json`) does not exist; the preflight
block lives inside `perf-lab.json` instead. Substance is present, path drifted.

---

## 6. Findings

### F-1 — The gate does not pass; two of the three red checks are missing evidence
**BLOCKER · certain.** `tools/gate.sh performance-stress-places` → exit 1,
`FAIL_RECOVERABLE`.
*Location:* `artifacts/performance-stress-places/gate.json` (`status`);
`artifacts/performance-stress-places/prior-gates.txt` (absent);
`artifacts/performance-stress-places/reviews/` (2 of 4 reports absent);
`artifacts/performance-stress-places/consumer-impact.md` (missing the pinned string).
*Reproduction:* `tools/gate.sh performance-stress-places; echo $?` → `1`;
`python3 tools/check_perf_gate_evidence.py prior-gates` → `FileNotFoundError`.
*Violated requirement:* PL-20 (prior gates unregressed at final source), PL-21
(fresh-context reviews), PL-19 (consumer ledger); UI-AGENT-001.
*Smallest corrective test:* run `tools/prior_gates.sh` at the final source, land the
supplement, land the two missing review reports, add the `was NOT re-run` sentence,
then rerun `tools/gate.sh performance-stress-places` and require exit 0.

### F-2 — The live MicroProfiler read-back observed 8 of the 9 declared scopes, and the gate check pins the wrong number
**MAJOR · high confidence.** `src/core/profile.luau` declares **nine** scopes —
`arrange, commit, measure, mount, mutate, react, reset, resource, scenario` (I
extracted them from the `SCOPES` table). `decisions.md` PLN-2 correctly says nine.
But `artifacts/performance-stress-places/studio/perf-lab.json.microprofilerScopes`
lists **eight** timers (no `LuauUI/reset`), sets `"allEightDeclaredScopesVisible": true`,
and asserts *"the eight names are the whole closed set from `src/core/profile.luau`"* —
which is false. Worse, `tools/check_perf_gate_evidence.py::scopes` hard-asserts
`len(d["timers"]) == 8`, so **correcting the artifact to the truth reddens the gate**
(mutation E2 → `FAIL — 9`).
*Location:* `artifacts/performance-stress-places/studio/perf-lab.json` keys
`microprofilerScopes.timers`, `.allEightDeclaredScopesVisible`, `.note`;
`tools/check_perf_gate_evidence.py` `def scopes()`.
*Reproduction:* append `{"id":999,"name":"LuauUI/reset"}` to `.timers`, run
`python3 tools/check_perf_gate_evidence.py scopes` → `FAIL — 9`.
*Mitigating fact:* `reset` **is** exercised — `pl9-capture-set.json.rows[0].scopes.byScope`
contains `"reset": 1`. The defect is in the labelling and in the check that freezes it,
not in the scope set.
*Violated requirement:* PL-8 ("a live LibMP read-back" of the declared set); the
manifest note claims *"the cardinality rule observed rather than asserted"*.
*Smallest corrective test:* drive one `reset` while the LibMP capture is open, record
nine timers, and change the assertion to
`set(t["name"] for t in timers) == {"LuauUI/"+k for k in profile.SCOPES}` — derived from
the source, so it cannot drift from it again.

### F-3 — `optimization-log.md` claims other scene budgets are "byte-identical"; nine float fields moved
**MINOR · certain.** `optimization-log.md` L-4 §Budgets: *"the tool … touches only the
named scenes … every other scene's budget is byte-identical."* Against `HEAD`,
`bench/perf_budgets.json` changed 9 float fields across 5 other scenes
(`async-image-burst.total_p95_ms`, `dense-hud.total_p95_ms`,
`native-scroll-drag.observed_p95_{max_,}ms`, `theme-swap-flat.observed_p95_{max_,}ms`
and `.total_p95_ms`, `virtual-list-scroll.observed_p95_{max_,}ms`).
*Magnitude:* ~1.1–1.6 × 10⁻¹⁶ relative — a JSON re-serialization ULP, numerically
irrelevant, and it moves in **both** directions so nothing was loosened in substance.
*Reproduction:* `git diff bench/perf_budgets.json`; the tool's own behaviour is clean —
I ran `lune run tools/lune/perf_baseline_scene lab-dense-scroll` and only that scene
changed. The drift is a one-time artefact of the first full re-serialization.
*Violated requirement:* PL-17 (record the loop accurately). *Corrective test:* soften
the sentence to "value-identical to within float round-trip", or have the tool preserve
untouched entries as raw text.

### F-4 — `reviews/README.md` presents four reviews as delivered while two reports do not exist
**MAJOR · certain.** `reviews/README.md` line 3 ("Four independent reviews") and the
table rows 9–11 link `phase-gate.md`, `architecture.md`, `reactive-runtime.md`. At the
reviewed source only `README.md` and `roblox-platform.md` exist.
*Reproduction:* `ls artifacts/performance-stress-places/reviews/`.
*Credit where due:* the `fresh-context-reviews` gate check **catches this** — it
`test -f`s all four and is red. The finding is that the summary artifact asserts a
state its own gate check contradicts.
*Corrective test:* the existing check is already correct; land the two reports.

### F-5 — `tools/check_perf_place.py` hardcodes a developer filesystem path
**MINOR · certain.** Line 119:
`env["PATH"] = "/Users/josha/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:" + env.get("PATH", "")`.
A checked-in tool whose stated purpose includes refusing `"/Users/"` inside the built
place carries an absolute developer path itself. It degrades safely (the prepend is
additive), so this is portability, not correctness.
*Corrective test:* drop the prepend and let `rojo` resolve from `PATH`; assert a clear
error if it is not found.

### F-6 — The "runner is reused, not forked" check cannot fail for an edit to the runner
**MINOR · certain.** `examples/performance.project.json` maps
`"runner": { "$path": "gallery/scenarios/runner.luau" }`, and `check_perf_place.py`
compares the built tree's runner source against that same file. Both sides move
together, so mutation M3 (appending `-- MUTANT` to the runner) **passed**. It catches
only a repoint-to-a-diverged-copy (M4), and a byte-identical fork also passes (M5).
*Location:* `tools/check_perf_place.py` lines 170–180; `place.json.notes[0]`.
*Violated requirement:* none directly; the note *"reused, not forked"* overstates what
was proven (byte-identity of whatever the project points at).
*Corrective test:* assert on the project file that the `$path` resolves to
`examples/gallery/scenarios/runner.luau`, which is the property actually intended.

### F-7 — Capture admissibility refuses only the exact token `"unknown"`; the shipped rows carry unrecorded conditions
**MINOR · certain.** `tools/check_perf_captures.py::missing` treats a field as absent
only for `None`, `""`, or exactly `"unknown"`. All six shipped rows carry
`thermalNote: "not recorded"` and `frameTarget: "uncapped/unknown"` and are declared
admissible. `"unknown/unrecorded"` also passes (mutation C4b), while bare `"unknown"`
fails (C4a).
*Location:* `tools/check_perf_captures.py` lines 53–60;
`studio/pl9-capture-set.json.rows[*].thermalNote` / `.frameTarget`.
*Defence on record:* `decisions.md` PLN-3 explicitly blesses `"n/a"` / `"not recorded"`
as declarations rather than ignorance — a reasonable rule for a desktop Studio host.
The residual risk is that the plan requires *power/thermal conditions* for the device
rows, and the same lenient rule will apply to a `phone-physical` row where thermal
state is load-bearing.
*Corrective test:* require a non-declarative value for `thermalNote` and `frameTarget`
when `evidenceClass in DEVICE_CLASSES`.

### F-8 — Only 2 of the 4 `measure_memo.spec.luau` cases discriminate
**MINOR · medium confidence.** Removing both replay assignments
(`ctx.compact[node.id] = hit.compact`, `ctx.textFacts[node.id] = hit.textFacts`)
reddened `seed 612` and `seed 91` but **not** `seed 132: a compact label that FITS is
not marked compact by a stale measure`, nor the geometry case (the latter is a
deliberate control — the finding was that geometry did *not* move).
*Location:* `tests/measure_memo.spec.luau` lines 54–75.
*Reproduction:* apply the two-line deletion, `./run-tests.sh` → `2 failed, 3364 passed`,
failures are `seed 612` and `seed 91` only.
*Assessment:* the pin is real and the BLOCKER fix is genuinely proved by two cases;
`seed 132` is coverage, not a control. Worth either strengthening or relabelling so a
future reader does not count four biting cases.

### F-9 — The memo's stated safety argument is inaccurate about `ctx.diagnostics`
**MINOR · high confidence on the claim, low on impact.** `src/layout/solver.luau`, the
`PER-SOLVE MEMO` comment: *"every side effect `measure` has is an idempotent write into
a ctx table keyed by `node.id`."* There are 12 `table.insert(ctx.diagnostics, …)` call
sites in `solver.luau` (lines 446, 533, 979, 1163, 1177, 1200, 1214, 1367, 1409, 1461,
1519, 1683), several reachable from the measure path. An append is not an idempotent
keyed write: on a cache hit the diagnostic is not re-appended, so a node previously
measured twice now contributes one diagnostic instead of two.
*Why this is probably benign:* de-duplication is the desirable direction, the suite
(including the `text_audit` determinism case) is green, and the architecture review's
differential fuzz reported `rectDiff=0`. But the fuzz compared rects and the two
verdict channels — I saw no evidence it compared the `diagnostics` list, which is the
channel this specific claim covers.
*Smallest corrective test:* extend the differential oracle to diff
`result.diagnostics` (as a multiset) with the memo bypassed vs active over the same
800 seeded trees; if counts differ, correct the comment and record the change as
intended.

---

## 7. What I did not run, and why

- **PL-P1 / PL-P2 (physical Android).** No hardware; correctly `PENDING_PHYSICAL`. I
  verified only that nothing substitutes for them — see G4, C2, C3.
- **PL-P3 (open the emitted `.rbxl` via File → Open from File).** Requires a human GUI
  action. I verified the adjacent facts instead: the build is deterministic and the
  checked-in file is byte-identical to a fresh build of current source (G12).
- **Re-driving the Studio sessions.** The six Play sessions and the LibMP capture cannot
  be replayed headlessly. I audited their artifacts against the checkers and mutation-
  tested the checkers (E1, E2). This is why F-2 matters: for Studio rows the checker is
  the only remaining adversary, so a checker that pins a false number is load-bearing.
- **Reproducing the architecture review's 800-tree fuzz.** Out of scope for this review
  and already re-verified indirectly by mutation S1.

## 8. Repository state after this review

All temporary mutations were reverted and confirmed: `src/layout/solver.luau`,
`examples/performance.project.json`, `examples/gallery/scenarios/runner.luau`,
`examples/performance/lab/{dataset,rows}.luau`, `bench/perf_budgets.json`,
`artifacts/phase-4/perf.json`, `acceptance.md`, `studio/{pl9-capture-set,perf-lab,device-matrix}.json`.
The scratch fork `examples/performance/lab_runner_fork.luau` was deleted.
`examples/places/LuauUI-PerformanceLab.rbxl` and `place.json` / `captures.json` /
`gate.json` were regenerated by the checkers themselves, which is their documented
behaviour; the place matches a fresh deterministic build of current source.
