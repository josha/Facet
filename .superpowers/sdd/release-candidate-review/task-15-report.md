# Wave T15 — report

**Status: COMPLETE for the headless/build half. Two CONTESTED items, both with
measurements and named blockers.** No Studio capture taken, no push, no subagents.

Base `d8aa27e` (suite 6808) / Rascal Rally `fccf29d` (3449).
Evidence: `artifacts/release-candidate-review/perf/requalification.md` and
`artifacts/release-candidate-review/perf/capture-plan.md`.

---

## Per-item outcomes

**1. Lab refresh + verification — DONE.** `check_perf_place.py` PASS (rebuilt from
source; 17 required instances, 5 version markers, publish-safe). **The checked-in
`.rbxl` was three days stale** — 2,538,179 bytes built 08-18 against 2,721,018 on
rebuild — so any capture taken from it in that window was of a place that did not
match the repository. All **17** workloads select, mount, run every declared pass,
reset, and reproduce their seed digest headlessly; `dense-scroll-native` refuses to
mount by design (a host seam) and says so by name. The registry-vs-runner contract
spec is green. Each release wave the brief flagged was checked against the runtime
rather than assumed.

**2. Headless perf suite — PASS.** 20 scenes × 5 profiles, every budget and the
one-way frame ceiling held. **The Controls indirection is proved ≤ noise**: the hop
in isolation is +0.000004 ms, and namespace-vs-legacy across three runs is −0.04% /
+1.93% / +1.17% — it changes sign. Construction-only, never per frame. No
optimization.

**3. RR-5 / RR-12 — measured, then fixed only where measured.**
- RR-5's 25-site list was three consolidation waves stale. Re-derived two ways
  (static literal scan + a runtime instrument counting VALUE-equal recomputes) to
  **38 sites**; one of the original 25 was `core:memo(` quoted inside an error
  STRING and is not a memo.
- Arm B (value-eq everywhere) moves the adapter op log **by zero writes across all
  twenty scenes** — the renderer already diffs — so the cost had to be read at the
  SOLVE layer, where it is real.
- RR-12: measured first (per-flush allocation and time), then optimized because a
  scene showed it — the one-observer `notify` fast path.
- PLAT-20: OPEN and untouched. It is an Instance allocation; headless has no
  `Instance`, so no headless instrument can see it. Routed to the Studio rows.

**4. Counters current — DONE.** The lab had two separately written counter
literals that had drifted both ways: the renderer's structural counters were on the
live read and not the capture row, and the **haptics counters were in neither** —
readable on screen during a capture and absent from the artifact that capture
produced. One `liveCounters()` now serves both; haptics became a table (the overlay
string is derived from it), and the text-premeasure queue was added. Theme-swap
counters audited and already current. Held by a BY-SET comparison plus a
named-counter case; both mutations bite.

**5. Capture readiness — DONE, and it found a live defect.**
`tools/microprofiler_aggregate.py` filtered scopes on a hard-coded `Facet/`, and
**every dump this project owns predates the rename and carries `LuauUI/*`** — so
the default invocation printed an empty table for the entire corpus, which reads as
"the framework did no work". Fixed (both prefixes, the legacy one announced, an
explicit sentence when nothing matches) and given a `--selftest` that synthesises a
dump carrying one scope of each prefix; two mutations bite. Scope-label balance
re-verified (15 cases). **The guide had lost three workloads** — "the fourteen" vs
seventeen declared, the three missing being the NAMED LEVERS aimed at the top cost
in every device capture ever taken; corrected and mechanised in three directions,
three mutations bite. `capture-plan.md` written: 13 ordered rows with settings,
warm-up, window, expected counters, and the two rows this wave changed marked as
owing a re-capture.

**6. Evidence — DONE.** `perf/requalification.md` (8 sections, 6 concerns). RC-22
moves from bare PENDING to a run string covering the headless half only, ending in
the explicit sentence that the Studio and Android rows stay with the close-out. The
findings ledger's Perf-wave row moves QUEUED → the same honest split.

**7. Memory workstream — MEASURED; the one seam that pays is CONTESTED.** Table
below. The instrument for the Studio half shipped (module-load marks). The lazy
structure did not ship, for one reason stated in full in §7 of the artifact.

---

## The memory table — headline

> **RETRACTED 2026-08-21 (M2-review finding A-M1).** Every number in this section
> is SUPERSEDED and none of it is a saving. It was measured one subset per process
> with no settle before the mark, so the root row is bimodal (collector phase, not
> memory), and the subset arithmetic charges each control for the shared graph
> `src/init.luau` loads anyway. The A/B on the real file says **228 KB [131..313]**
> shipped and **860 KB [762..860]** at the ceiling —
> `artifacts/release-candidate-review/perf/requalification.md` §7, which now also
> carries this table under its own SUPERSEDED heading with the ranking that
> survived. Kept here unedited because it is what this report said on the day.

Live Lua heap retained after `require`, one subset per process, 9 repeats, median.

| subset | KB | vs root |
|---|---|---|
| **`require(Facet)`** | **2 797** | — |
| root minus the 19 composite controls | 1 966 | **−831 KB (−29.7%)** ← whole saving |
| …+ `ProgressView` only | 1 998 | −799 (−28.6%) |
| …+ the three Rascal Rally builds | 2 247 | **−550 KB (−19.7%)** ← biggest realistic subset |
| …+ `Table` only | 2 291 | −506 (−18.1%) |

**Every other candidate the brief named is noise**, measured as a marginal on top of
that floor: `themes/package` 0 KB (already pulled transitively), the drag/gesture
family 13, `replication/adapters` 11, `controls/path_shapes` 7, `input/spatial`
inside the ±15 KB band, `sensory_profile` 23 standalone. `themes/snapshot` (299 KB)
cannot be deferred at all — `env/environment` requires it. `blueprint_schema`
(536 KB) is a hot path, which the brief's own rule excludes.

**Why it did not ship.** The mechanism is proved at runtime:
`type M = typeof(require("@self/controls/table"))` costs **0 KB and does not load
the module** while keeping `M.Spec` as a type, so all 19 typed signatures survive a
deferred require and only `src/init.luau` changes — **no locked or off-limits file
is involved**. But there is **no Luau analyzer anywhere in this toolchain and no
gate row typechecks**, so the change's entire justification ("the typed signatures
survive") is a claim no instrument here can falsify. Shipping that at
release-candidate stage is the class this repo refuses. One analyzer gate row
unblocks a one-file, 831 KB change, and `Facet.preload()` ships beside it.

---

## RR-5 disposition counts (38 sites)

| disposition | n |
|---|---|
| **FIXED, measured** | **4** |
| **CONTESTED — measured real, blocked by a source-cap lock** | **2** |
| NOISE — exercised, moved no scene | 18 |
| UNMEASURED — no scene or workload reaches them | 14 |
| NOT A SITE (`core:memo(` inside an error string) | 1 |

- Fixed: `virtual_window.luau` `canvasDim`; `virtual_grid.luau` `canvasDim`,
  `extentDim`, `virtualSlot`. Eq is `rect.sameFlatValue`, the framework's existing
  flat-record equality (already the renderer's `sameGeometryValue` and the selection
  indicator's `sameGeometry`). Both fixes red-first via churn-counter specs.
- Contested: `virtual_list.luau:3234` (`rowExtentDim`; moves `variable-extents`
  246→223 solves — the file is 7,813 chars from the write cap and its ledger row
  says the hosted-block extraction must PRECEDE the next change of any size) and
  `table.luau:1968` (`canvasHeight`; moves `table-unified` 38→28 — `table.luau` was
  OFF-LIMITS to this wave and its own trigger has fired). Both are the same
  construct as the two that were fixed and each is one argument long.

**Measured effect of what shipped:** `lab-collection-churn` 41 solves → 1 over 40
churn iterations, all 40 producing zero rect and zero prop writes; lab
`variable-extents` 294→246, `edit-locality` 131→83 (partial 53→29),
`collection-churn` 30→25; VirtualGrid 57 measure-dirties → 0 on a no-op off-window
edit. Scene p95 `lab-collection-churn` 1.50 ms → 0.14 ms.

**RR-12 effect:** `animation-interruption` 0.347→0.106 ms (−69%),
`collection-mutation` 1.214→0.864 (−29%), `hud-binding-storm` 0.220→0.206 (−6%),
five interleaved samples a side.

---

## Commits (framework `main`, not pushed)

| sha | subject |
|---|---|
| `1bde05e` | the review said twenty-five memos re-dirty the tree; four of them actually do |
| `3256ce8` | the flush's biggest allocation was a sorted list of one |
| `fc83c3c` | the counter you could read on screen was the one the capture did not carry |
| `205de01` | three marks, and only the bootstrap can take the first one |
| `29dc917` | the summary tool read every device capture we own as an empty table |
| `b9c7c8b` | the numbers, and the five instruments that produced them |

Rascal Rally: **no commit, by design.** This is a compatible internal change; the
consumer suite is green at 3449 against the changed Facet source and the standing
`facet_public_surface_currency` contract is green. Measured on the SHIPPED sponsor
racer list (24 rows, six 250 ms republishes, the production `Controls.VirtualList`
path): the solve count is +7 with and without the RR-5 fix — that list's every-tick
republish carries real content changes, so the fix is behaviour-neutral there
rather than a win, and a game-side test asserting "no change" would have been a
check that proves nothing.

---

## Tails

```
./run-tests.sh                                 6821 passed      (base 6808; +13 new cases)
RascalRally ./run-tests.sh                     3449 passed      (unchanged)
tools/perf.sh          perf: PASS (100 runs, 20 scenes) [artifacts/phase-4/perf.json]
check_perf_place       PASS — 17 required instances, 5 version markers, publish-safe
check_perf_scenes      7 production scenes alive at floorAndroid
check_perf_metrics     100 headless records carry all 7 metric rows; 0 device rows
check_perf_budgets     20 scene budgets; 3 device budgets declared and unmeasured
check_perf_captures    PASS — 18 rows admissible, classes={'studio': 18}, 0 device rows
check_perf_gate_evidence scopes/headless-linkage/falsifiable/perf-gate/budgets — all PASS
profile_scopes spec    15 passed (balance on every exit path)
microprofiler_aggregate --selftest  PASS — container, header, 3 records, 1 layout record, both prefixes
public surface         BYTE-IDENTICAL to artifacts/release-candidate-review/public-surface.txt
check_boundary         PASS (155 src files, 413 consumer files)
check_registration     PASS (38 controls, 99 exports, 255 specs)
check_source_size      PASS — 6 modules in the band, all with ledger rows
```

---

## Concerns

1. **A whole control family is outside the measurement surface.** No bench scene
   and no lab workload mounts a `VirtualGrid` or a `RowActions` tray. That is
   exactly why four real RR-5 sites in `virtual_grid.luau` measured zero — nothing
   ran them — and why the grid fix had to be proved by a spec instead of a scene.
   The row-actions half is still unmeasured.
2. **Two measured RR-5 sites are blocked by source-cap locks**, and they are the
   same one-argument construct as the two that shipped. `virtual_list.luau` owes its
   hosted-block extraction; `table.luau` was off-limits.
3. **The public type surface has no mechanical guard at all** — no analyzer, no
   gate row. It blocked an 831 KB memory win here and will block the next claim
   that rests on a type.
4. **The built place carries no comparable build stamp.** It was three days stale
   and only a rebuild revealed it. `Facet_SourceStamp` is already READ by the
   capture facts; nothing WRITES it at build time.
5. **No MicroProfiler dump is in the repository.** `--selftest` closes the decoder
   half; "does a real client still emit this shape" can only be answered by a real
   dump, and every one lives outside the tree. `.gitignore`'s existing
   irreproducible-evidence exception would cover one.
6. **`screen-lifecycle-churn` is not a usable trend signal on this host** — it swung
   1.23→3.57 ms across provably identical arms. A first, non-interleaved reading of
   it looked like a clean +1.3 ms regression from the RR-5 fix and was noise.
7. **Another agent was working in this tree concurrently.** All six commits went
   through `tools/commit_isolated.py` with named paths; each commit's file list was
   verified afterwards and none carries the other agent's work. I stopped using
   `git stash` for A/B arms after one shared-index run hung, and used file copies
   instead.

---

# Addendum — the director's lazy-loading ruling, and the T15 review

**Status: EXECUTED, with one finding that reverses part of the ruling's premise
and one that reverses part of my own report.** The analyzer the director ordered
pinned is what produced both.

## Analyzer chosen + version

**`luau-lsp@1.69.0`** (JohnnyMorganz/luau-lsp, `analyze` mode), pinned in
`rokit.toml` beside Rojo. It installs and runs on this platform today; upstream
`luau-analyze` was not needed. **No Roblox definitions file**: the library imports
no engine globals at its own boundary, so `--platform standard` types the whole
require graph, and keeping it out is what stops this becoming a lint regime.
0.16 s over `src/init.luau`.

## The witness check, red and green

`tools/check_types.py` gates the diagnostics of **two** target files —
`src/init.luau` and `tests/types/controls_witness.luau`, which exercises all 19
`Facet.Controls` signatures — and **ignores the 246 pre-existing diagnostics in
the require graph** by design.

Two halves, neither sufficient alone. The **positive witness** hands each entry a
local declared with the control module's own `Spec`, so a wrong or narrowed
parameter type reddens. The **generated negative probe** hands each entry a
number: the 15 typed entries must reject it, and the 4 that take `any` today
(`Chip`, `VirtualList`, `VirtualGrid`, `AsyncImage`) are pinned by name so the set
cannot grow.

```
check_types: PASS — 19 Controls entries (15 typed, 4 declared `any`);
             2 target files carry 0 diagnostics; 246 graph diagnostics ignored

check_types --selftest: PASS
  [ok] unmutated                                  (PASS expected)
  [ok] M1 Controls.Table widened to `any`         (FAIL expected)  <- the lazy-without-types shape
  [ok] M2 Controls.Slider given the wrong Spec    (FAIL expected)
  [ok] M3 witness stops using a real Spec         (FAIL expected)  <- via the unused-local lint
```

**M1 is the director's second red-first case and it bites on the real thing**: the
all-nineteen arm runs **green in the Luau suite** and fails this check naming all
15 lost signatures. Nothing else in the repository can see that.

### What the instrument falsified

`typeof(require(x))` does **not** carry a module's exported types. Measured, all
four spellings answer `TypeError: Unknown type 'M.Spec'`:

| spelling | result |
|---|---|
| `type M = typeof(require(x))` | `Unknown type 'M.Spec'` |
| `local M = (nil :: any) :: typeof(require(x))` | `Unknown type 'M.Spec'` |
| `local M: typeof(require(x)) = (nil :: any)` | `Unknown type 'M.Spec'` |
| `local M = if false then require(x) else (nil :: any)` | `Unknown type 'M.Spec'` |
| `local M = require(x)` (the eager control) | clean |

Only a direct `require` binding brings exported types into scope. So 15 of the 19
cannot be deferred from `src/init.luau` alone without widening to `any`.

## Realized memory numbers

**The 831 KB headline in §7 was wrong and is corrected.** It was subset
arithmetic — each control charged for the shared dependency graph `src/init.luau`
loads anyway — and the review showed the root row is bimodal (2,574–2,816 KB),
i.e. collector phase rather than memory. Every mark now follows an identical
settle; arms run interleaved; each arm's samples split into its two collector
modes and compared low-mode to low-mode.

**n = 30 rounds per arm:**

| arm | low mode | median | low-mode range |
|---|---|---|---|
| eager (today) | 19/30 | 2 763 KB | [2 666 .. 2 763] |
| **shipped — 4 deferred** | 17/30 | **2 535 KB** | [2 450 .. 2 535] |
| ceiling — all 19 (types sacrificed) | 14/30 | 1 903 KB | [1 903 .. 1 904] |

| | median saving | conservative range | require time |
|---|---|---|---|
| **shipped** | **228 KB** | **[131 .. 313] KB** | 209 ms vs 227 ms |
| ceiling | 860 KB | [762 .. 860] KB | 157 ms vs 227 ms |

After first mount, the deferred module loads at the construction seam; `preload()`
force-loads all four and returns 4. The remaining **632 KB** needs the 15 `export
type Spec` declarations moved to a module that costs nothing to load — which
touches `table.luau` (off-limits), `virtual_list.luau` and `row_actions.luau`
(locked) plus twelve others, so it is a scoped follow-up, not a change to
`src/init.luau`.

**Public surface, proved in two parts because the claim is in two parts:** the
lazy mechanism alone is **byte-identical** to the frozen dump; `preload` then adds
**exactly one line** (`preload : function`), documented in the api reference and
the capability catalog — both guards refused it until it was.

## The review's three red rows — all mine, all green

The reviewer's core point stands and I have taken it: my verification tail was a
hand-picked list, not the gate-row set.

| row | cause | fix |
|---|---|---|
| comments-plain | 6 `RR-5`/`RR-12` codes I wrote resolved nowhere | each site now STATES the finding in plain language; the bare codes are gone (they also broke the 25-code ratchet) |
| product-language | 11 `LuauUI/` strings in `microprofiler_aggregate.py` — correctly there | allowlisted with reason + trigger, scoped to the PREFIX so ordinary old-brand text in that tool is still caught |
| call-shape drift | `_probe_t15_controls.luau` calls the retiring form — because it MEASURES it | allowlisted with the same discipline the compatibility spec has |

A **fourth** turned up only because I extracted the gate row's shell text and ran
it: the maintainer map that landed alongside this wave cites earned gate ids
(`swiftui-parity-round4`) and lacked the `GATE_IDS` entry six other files already
carry. Added.

```
naming-adr-implemented (extracted and run verbatim)  exit=0
```

## Capture plan

- **`cleanCapture` was silently dropped.** It is a STEP, not a `select` setting,
  and `steps.select` skipped unparsable pairs without a word — so every planned
  row would have captured with the overlay mounted while claiming otherwise. The
  parser now **refuses** an unparsable pair by name and suggests the legal
  spelling, **in its own pass before anything is applied** (the first cut left
  `rows` written and the spec caught it). Plan respelled.
- **`render.solves` is `nil` on 8 of 17 workloads** — every `implementation =
  "none"` row, including both that owe a re-capture. Those publish their own
  arithmetic in the pass detail; the plan now names the real fields per row, read
  off the live registry (`arrangePerEdit` / `partialSolvesPerEdit`,
  `uniform.arrangePerGrow`, `arrangePerRep` / `usPerArrangedNode`, …).

## Rascal Rally

Five paired rounds through the real sponsor boot:

| | eager | shipped | delta |
|---|---|---|---|
| require heap | 2 662 KB | 2 531 KB | −131 KB |
| require time | 232 ms | 209 ms | −23 ms |
| boot (present + 8 frames) | 45.1 ms | 58.6 ms | **+13.5 ms** |
| require + boot | 277 ms | 268 ms | −9 ms |

The cost **moved** to first construction rather than appearing; both halves happen
inside the game's loading sequence and the total falls slightly. Suite **3449**
green against the shipped Facet, no game edit, and `preload()` is there if the
game would rather pay at require after all.

## Tails

```
./run-tests.sh (isolated clone of HEAD + my files)   6844 passed
RascalRally ./run-tests.sh                           3449 passed
check_types / --selftest                             PASS / PASS
naming-adr-implemented row, verbatim                 exit 0
check_comment_codes    PASS — 0 orphans, 25 codes (ceiling 25)
check_brand_drift      PASS + SELFTEST PASS
check_call_shape_drift PASS + SELFTEST PASS
public surface         lazy alone BYTE-IDENTICAL; +1 line with preload
check_registration     PASS (100 exports documented)
check_docs             PASS
tools/perf.sh          PASS (100 runs, 20 scenes)
stylua --check         PASS
```

**Verification note:** another agent's in-flight edits to `src/blueprint.luau`
and two specs were red in the shared tree throughout. Every number above was taken
in an isolated clone of HEAD carrying only my files, which is how I know which
failures were mine — and is the practice I should have been using from the start.

## Commits (addendum)

| sha | subject |
|---|---|
| `45fc2c6` | the analyzer's first act was to falsify the idiom that summoned it |
| `e3aeda4` | three red gate rows my own report called green, and the guard entries they wanted |
| `84b38bb` | a settings string that meant less than it said, and a plan that read a nil counter |
