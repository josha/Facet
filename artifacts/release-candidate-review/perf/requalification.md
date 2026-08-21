# RC-22 — release performance requalification (headless + build half)

**Wave T15.** Base: framework `d8aa27e` (suite 6808), Rascal Rally `fccf29d`
(3449). Everything below is headless or buildable. **The Studio MicroProfiler
rows and the low-end Android row are NOT here and are not claimed** — they are
the controller's and the device's, and the ordered plan they run is
[`capture-plan.md`](capture-plan.md).

---

## 1. Lab refresh and verification

`python3 tools/check_perf_place.py` rebuilds `examples/places/Facet-PerformanceLab.rbxl`
from current source and inspects the resulting tree.

```
check_perf_place: PASS — 17 required instances, 5 version markers, publish-safe
```

**The checked-in place was stale and nothing said so.** It was built 2026-08-18 at
2,538,179 bytes; rebuilding from the same project file on 2026-08-21 produced
2,721,018 bytes. Three days and several waves of lab source had landed in between,
so any capture taken from the checked-in artifact in that window would have been of
a place that did not match its own repository. The doctor rebuilds by default,
which is why this was found rather than shipped — but the artifact itself carries
no build stamp a reader can compare, and that is recorded below as a concern.

### The scenario registry against the current runtime

All **17** declared workloads were selected, mounted, driven through every declared
pass, reset, and re-selected at the same seed
(`tools/lune/_probe_t15_sweep.luau`):

| result | count |
|---|---|
| booted and mounted | 16 |
| refused mounting, by design | 1 (`dense-scroll-native` — the raw-Roblox reference is a HOST seam and says so by name) |
| every declared pass ran without "unknown pass" | 17 of 17 |
| deterministic reset, then the same seed reproduced the same dataset digest | 17 of 17 |

The digest is `e38aeda7` for every workload on `content=normal` and `4cfd9748` for
`large-text-overflow`, which selects `content=identity` — i.e. the digest varies
with the thing that is supposed to vary it and with nothing else.

The release waves the brief flagged were each checked against the runtime rather
than assumed:

| wave | what it changed | state |
|---|---|---|
| haptics (task 11) | overlay counters + a `select:haptics=on` selector | present, driven, and now also on the capture row (§4) |
| naming (ADR-0037) | `Facet.Controls.<Name>` call shapes | the lab and the bench both call the namespace; the indirection is measured in §2 |
| per-theme artifacts | theme packages out of the model | the lab maps `examples/themes` as `FacetThemes` and `fantasy_ornate` is a required instance in the doctor |
| the paradigm campaign | expand/collapse, carousel snap, the ten-foot metric ladder, grid intrinsic lanes, the 900 px measure cap | no scenario reads any of them directly; the suite covers them and the registry contract spec is green |
| the DIR wave | composition give-way | no lab dependency; `large-text-overflow`'s `revealAudit` pass runs |

The shared-runner contract (`tests/perf_lab.spec.luau`) is green: every
`registry.<field>` the gallery's runner reads is exported by the lab, asserted by
reading the runner's source rather than by pinning today's field list.

---

## 2. Headless perf suite

`tools/perf.sh` — 20 scenes × 5 profiles, reference `floorAndroid` @ 30 Hz.

```
perf: PASS (100 runs, 20 scenes) [artifact: artifacts/phase-4/perf.json]
```

Every scene is inside its trend budget and inside the 8.333 ms one-way frame
ceiling. Two scenes moved materially in this wave and both moved DOWN; they are
attributed in §3.

### The Controls indirection (`Facet.Controls.<Name>`)

The brief asked whether the naming wave's indirection shows in any scene. It is
one Luau call frame between the author and `<control>.build`, at CONSTRUCTION only
— never per frame. Measured directly (`tools/lune/_probe_t15_controls.luau`, three
runs):

| | ms |
|---|---|
| `Facet.Controls.ProgressView(core, spec)` | 0.01301 / 0.01270 / 0.01246 per construction |
| `Facet.newProgressView(Facet, core, spec)` (the builder direct) | 0.01301 / 0.01246 / 0.01232 per construction |
| **the hop itself, isolated from the construction** | **+0.000004 ms** |

The difference between the two spellings is −0.04% / +1.93% / +1.17% across three
runs — it changes SIGN, which is the definition of noise. The hop in isolation is
four nanoseconds, 0.03% of the cheapest composite's construction cost. **Proved
≤ noise; no optimization.**

---

## 3. RR-5 and RR-12

### RR-5 — memos returning a fresh table under identity eq

The review's list of 25 sites predates three waves of consolidation, so it was
re-derived two ways.

- **Statically**: memos whose compute returns a table LITERAL and declare no eq —
  **24 real sites in `src/`**. (The static scan found 25; one,
  `src/tokens/styling.luau:449`, is `core:memo(` quoted inside an ERROR STRING and
  is not a memo at all.)
- **At runtime**: `core.memo` wrapped to count recomputes whose result was
  VALUE-equal to the previous one — **14 further sites** the static scan cannot
  see, because they return a helper's table rather than a literal.

**Canonical population: 38 sites. 24 of them are reached by some bench scene or
lab workload; 14 are not.**

#### The measurement, and why it had to be read at the solve layer

Arm A is the shipped default. Arm B supplies value-eq to every memo that declared
none — the most the fix could ever buy. Across all twenty bench scenes the adapter
op log does not move **by a single write**: the renderer already diffs, so the
review's cost is structurally invisible at the write layer. It is real one layer
up. Per-site attribution (arm B applied to one site at a time):

| site | what it is | value-equal recomputes | scenes it moved |
|---|---|---|---|
| `virtual_window.luau` `canvasDim` | the virtual canvas extent | 80 of 84 (bench) / 263 of 514 (lab) | `lab-collection-churn` 41 → 1 solves; lab `variable-extents` 294 → 246; `edit-locality` 131 → 83 (partial 53 → 29); `collection-churn` 30 → 25 |
| `virtual_grid.luau` `canvasDim` + `extentDim` + `virtualSlot` | the same three constructs in the grid | not reachable — **no bench scene or lab workload mounts a grid** | 57 measure-dirties → 0 on a no-op off-window edit (the churn-counter spec IS the measurement) |
| `virtual_list.luau:3234` `rowExtentDim` | the per-row extent Dim | 1874 of 1963 | lab `variable-extents` 246 → 223 |
| `table.luau:1968` `canvasHeight` | the Table's virtual canvas extent | 12 of 13 | lab `table-unified` 38 → 28 |
| `virtual_list.luau:3257` `rowSlot` | the per-row slot promise | 1392 of 1446 | **none** |
| `virtual_list.luau:3241`, `:3525`, `virtual_window.luau:262`, `:280`, `table.luau:1386`, `env/environment.luau:214` | six more with a non-zero coalescable count | 1–168 each | **none** |
| the remaining 28 | | 0 | **none** |

The combined arm buys more than the sum of the singles — `variable-extents` goes
to 175 with every virtual-list-family site coalesced against 223 for the largest
single — so some waste is only removable once its upstream has stopped firing.
Recorded rather than attributed, because no single site owns it.

#### Dispositions

| disposition | count | sites |
|---|---|---|
| **FIXED, measured** | 4 | `virtual_window` `canvasDim`; `virtual_grid` `canvasDim`, `extentDim`, `virtualSlot` |
| **CONTESTED — measured real, blocked** | 2 | `virtual_list.luau:3234` (the file is extraction-locked at 192,187 chars; its own ledger row says the hosted-block extraction must PRECEDE the next change of any size) and `table.luau:1968` (`table.luau` is OFF-LIMITS this wave AND its ledger trigger has fired) |
| **NOISE — exercised, moved nothing** | 18 | the six with a non-zero coalescable count that moved no scene, plus twelve exercised sites that never produced a value-equal recompute at all |
| **UNMEASURED — no scene reaches them** | 14 | all four `virtual_grid` sites are now fixed regardless; the rest are `row_actions_root` ×2, `row_actions_trays` ×2, `progress_view` ×2, `table.luau:1815`, `virtual_list.luau:2446` and `:3485`, `environment.luau:508` |
| **NOT A SITE** | 1 | `tokens/styling.luau:449` — `core:memo(` inside an error message |

**THE TWO CONTESTED SITES HAVE AN OWNER AND A TRIGGER** (T15 review item 4; the
director ruled on the lazy work in the same round). Owner: whoever next opens
either file, because both are extraction-locked and the extraction is owed before
any change of any size. Trigger: `virtual_list.luau:3234` rides the
`virtual_list_hosted.luau` extraction its ledger row already names;
`table.luau:1968` rides the next authorized change to `table.luau`, which this
wave was explicitly forbidden. Neither is waiting on a decision — the fix is one
argument in each and it is written down here — only on the lock.

**The unmeasured 14 are a coverage finding, not a disposition.** No perf scene and
no lab workload mounts a `VirtualGrid` or a `RowActions` tray, so a whole shipped
control family is outside the measurement surface. The grid half of that was closed
here by asserting the property in a spec instead; the row-actions half is open and
is recorded in §8.

The eq used is `rect.sameFlatValue`, which the framework already owns twice over —
the renderer's `sameGeometryValue` and the selection indicator's `sameGeometry` are
the same function. It refuses a nested field rather than half-comparing it, which
is exactly right for a Dim.

**Scene effect** (`lab-collection-churn` p95, six samples with the fix, five
without, interleaved ABBA then ABABAB):

| | median p95 |
|---|---|
| before | 1.50 ms |
| after | 0.14 ms |

`screen-lifecycle-churn` appeared to regress by 1.3 ms in a first, non-interleaved
comparison. Interleaved it swings from 1.23 to 3.57 ms **in both arms**, which is
larger than the difference — it is noise on this host and is not claimed in either
direction. Recorded because the first reading was convincing and wrong.

### RR-12 — per-flush allocation

**What could not be measured, first.** Lune has no forced collection, and this
repository already learned what a `gcinfo` pair is worth here
(`tools/lune/bench.luau`'s header: a sign that flips and a magnitude that
overstated retention ~17×). The per-scene `heapSlopeKbPerIter` in
`artifacts/phase-4/perf.json` proves it again — it ranges from **−1077 to +501 KB
per iteration** across twenty scenes, i.e. it reports collector phase, not
allocation. So allocation is estimated by summing only POSITIVE `gcinfo` window
deltas (a lower bound, never an overstatement) and reported beside flush TIME,
which is what a frame actually pays.

| shape | ≥ B/flush | ms/flush |
|---|---|---|
| bare signal, no subscriber | 484 | 0.0005 |
| 1 signal + 1 observer | 562 | 0.0008 |
| 10 observed memos on one signal | 2968 | 0.0104 |
| 50 observed memos on one signal | — (estimator drops collections at this rate) | 0.0508 |
| 50-deep memo chain | 3929 | 0.0256 |
| transaction of 20 writes, one flush | 3003 | 0.0127 |

**Then the thing the review did not say.** The snapshot-and-sort in `notify` buys
two properties and only one of them exists at a fan-out of ONE: order is real
(`node.observers` is a hash table), but a single observer has no order to
establish — and one observer per property is the ORDINARY shape of a mounted tree.
The safety half survives and is kept explicitly.

**A scene showed it**, which is the only reason the core was touched (perf.sh p95,
five interleaved samples a side):

| scene | before | after |
|---|---|---|
| `animation-interruption` | 0.347 ms | 0.106 ms (−69%) |
| `collection-mutation` | 1.214 ms | 0.864 ms (−29%) |
| `hud-binding-storm` | 0.220 ms | 0.206 ms (−6%) |
| `screen-lifecycle-churn` | 3.11 ms median | 1.73 ms median — **not claimed**, the scene's own swing is larger |

Six cases pin it (`tests/reactive_recovery.spec.luau`, RR-12) and four mutations
were proved to bite. Two of the six sit where they do because the obvious placement
proves nothing: a signal write already short-circuits on eq and never reaches
`notify`, so the value-equality case is built on a MEMO with a value eq; and the
`disposed` flag is UNREACHABLE at fan-out one, so it is pinned at fan-out two. A
fifth mutation — deleting the fast path's inner `pcall` — provably does NOT bite
and is recorded in the spec as such.

### PLAT-20

`src/client/text_premeasure.luau:165` allocates a `GetTextBoundsParams` Instance
per measured word and never destroys it. **Not measured and not touched in this
wave**: it is an Instance allocation on the client, headless has no `Instance`, and
no headless instrument can see it. It belongs with the Studio capture rows — the
counter that would show it is `render.textMeasureBatches` beside the client's
Instance census, both of which are now on the capture row (§4). Recorded as open.

---

## 4. Counter audit

The lab had **two** readers of its counter contract — the live `steps.counters`
and the exported CAPTURE ROW — as two separately written table literals, and they
had drifted in both directions.

| counter | before | now |
|---|---|---|
| renderer structural counters (`solves`, `partialSolves`, `creates`, `parked`, `recycled`, `rectWrites`, `propWrites`, `elided`, `textMeasureBatches`, `lastArranged`, `lastMeasured`) | live read only | both |
| haptics (`built`, `pooled`, `plays`, `coalesced`) | **neither** — overlay line only | both, as a table; the overlay's string is now derived from it |
| text premeasure queue (`controller.textPending`) | nowhere | both |
| module-load memory marks | did not exist | both (§7) |
| theme swap (`installMs`, `reflowMs`, `movedRects`, chrome census) | produced by the `themeSwap` pass, rides to the row inside `passes` | unchanged — audited and current |
| instances, connections, memory, core registry, provider | both | both |

One `liveCounters()` function is now what both readers call, so the next counter is
added once. Two spec cases hold it: the readers are compared BY SET (a counter
added to one tomorrow fails on the commit that adds it), and haptics / the render
block / the text queue are named individually, because a set comparison alone is
satisfied by two readers that are equally out of date. Both mutations bite.

---

## 5. Capture readiness

| item | state |
|---|---|
| scripted Studio capture procedure | `docs/guide/12-performance-lab.md` §12.4 — current, LibMP arming and the staleness assertion verified as written |
| MicroProfiler scope labels, balanced on every exit path | `tests/profile_scopes.spec.luau` — **15 passed**, including a throwing body, a throwing hook, nested unwinding, and a real render pass |
| capture metadata schema | `examples/performance/lab/capture.luau` — unchanged; `capture.problems` still refuses a row with any missing condition, `"unknown"` included |
| derived-summary tooling | `tools/microprofiler_aggregate.py` — **fixed and now self-testing**, see below |
| low-end Android instructions | §12.5 — current, Facet-named, procedure unchanged |
| the workload chapter | **was three workloads out of date**; corrected and mechanised |
| the ordered capture list for the controller | [`capture-plan.md`](capture-plan.md) — 13 rows |

**The summary tool read every device capture we own as an empty table.** Its scope
filter was hard-coded to `Facet/`, and every dump this project has ever taken
predates the rename and carries `LuauUI/*`. The default invocation printed the
header and no rows for all of them — which reads as "the framework did no work",
not as "this dump is from before the rename" — and silently lost the
`tick==window` staleness line with it. Both prefixes are recognised now, the
legacy one is announced, and a dump with no framework scopes gets an explicit
sentence instead of an empty table. Re-run on the two dumps that still exist: 12
scopes and `tick==60 (OK)` where there were none.

It also has a `--selftest` now, because until this wave a clone could not run the
decoder on anything: every real dump lives outside the repository. The selftest
synthesises a minimal well-formed dump carrying one `Facet/` scope and one
`LuauUI/` scope on purpose, and reverting the prefix fix reddens it.

**The chapter had lost three workloads.** It said "the fourteen workloads" while
the registry declared seventeen; `arrange-shapes`, `edit-locality` and `host-move`
— the three NAMED LEVERS, aimed at the top cost in every device capture taken —
were invisible to anyone who learned the lab from its own chapter. Corrected, and
the drift mechanised in three directions (every id has a row, the table invents
none, the spelled-out count is real). Three mutations bite.

**No capture was taken.** Studio is the controller's.

**2026-08-21 disposition (final-review H2): FAIL_ENVIRONMENT.** The controller's
Studio session can only drive the place that is already open (Facet-Showcase);
opening `examples/places/Facet-PerformanceLab.rbxl` is a human step the MCP has
no tool for. So every row in `capture-plan.md` — the 13 capture rows, the
MicroProfiler dumps, and the §2 module-load memory read — is blocked on
environment, not on readiness: the plan, the place check, and the instruments
were all verified current in this stage. Owner: the director opens the lab place
(or the next session starts with it open); the plan is then runnable as written.

---

## 6. What stays open — the controller's and the device's rows

- **Studio MicroProfiler baselines per scenario class.** `capture-plan.md`, rows
  1–13. Two of them (`edit-locality`, `variable-extents`) owe a re-capture against
  the stored before in `device-capture-2026-08-15.md`, because this wave changed
  exactly those two.
- **The low-end Android row.** `docs/guide/12-performance-lab.md` §12.5. Until it
  exists the honest statement is *automation complete, low-end performance not
  proven*, which is what `bench/perf_budgets.json` already declares by carrying
  `measured: false` on all three device budgets.
- **The Studio module-load memory read** (§7). The instrument shipped in this wave;
  the number is the controller's.

---

## 7. Memory: what the require graph costs, and whether lazy loading pays

The director's charge was to reduce Facet's memory requirements and ask whether
the code can load pieces on demand. **The table of numbers is the deliverable that
decides everything else**, so it is first.

### Method — and the correction the T15 review forced

**The first version of this section was measured badly and its headline did not
survive resampling.** It required one SUBSET per process, took a single `gcinfo()`
immediately afterwards, and reported the median of nine. The review resampled the
root row and found it **bimodal (2,574-2,816 KB)** — two collector phases, not two
memory costs — and a difference read off one pair of such samples is a difference
read off collector timing. Two things were wrong with it:

1. **the mark was taken without settling.** Lune has no forced collection, so a
   `gcinfo()` taken the instant a require returns reports wherever the collector
   happens to be. Every mark now follows an identical settle (allocate and drop a
   fixed churn), which puts the collector in a comparable place for every arm.
2. **subset arithmetic is not a deferral.** Requiring `controls/table` "alone with
   its deps" charges it for the whole shared graph — blueprint, solver, renderer,
   presenter — which `src/init.luau` loads anyway. That is what produced the
   original 831 KB figure. The number that means anything is an A/B on the REAL
   `src/init.luau`, one arm per file, which is what is reported below.

Samples are still one process per run (`require` is process-cached). Arms are run
INTERLEAVED, one sample each per round, so drift is shared; each arm's samples are
then split into the two collector modes and compared LOW-MODE TO LOW-MODE, because
comparing a settled sample against an unsettled one is the original mistake in a
new place. Driver: `tools/lune/_probe_t15_lazy_all.luau`.

### The measurement, n = 30 rounds per arm

| arm | low mode | median KB | low-mode range | high mode (settle uncollected) |
|---|---|---|---|---|
| eager — today's `src/init.luau` | 19 of 30 | **2 763** | [2 666 .. 2 763] | 11 @ ~4 957 |
| **shipped** — the four type-free entries deferred | 17 of 30 | **2 535** | [2 450 .. 2 535] | 13 @ ~4 832 |
| ceiling — all nineteen deferred (types sacrificed) | 14 of 30 | **1 903** | [1 903 .. 1 904] | 16 @ ~4 181 |

**Mode-matched saving against the eager arm:**

| arm | median saving | conservative range | require time (median) |
|---|---|---|---|
| **shipped (four deferred)** | **228 KB** | **[131 .. 313] KB** | 209 ms vs 227 ms |
| ceiling (all nineteen) | 860 KB | [762 .. 860] KB | 157 ms vs 227 ms |

The conservative range is worst-case against best-case across the two low modes,
not a confidence interval: it is the range a resampler should expect to land in,
which is the thing the first version of this section could not have said.

### What shipped, and what the ceiling costs

Deferring **four** of the nineteen — `Chip`, `VirtualList`, `VirtualGrid`,
`AsyncImage` — is worth **228 KB [131..313]** and costs no type at all, because
those four already declare `spec: any` and therefore need nothing from their
module at load. `Facet.preload()` force-loads them for a game that would rather
pay at the loading screen.

The other **632 KB** (860 minus 228) needs the fifteen entries that declare a real
`Spec`, and **that is blocked on a language fact, now measured rather than
assumed.** A module's exported types enter scope ONLY through a direct
`local M = require(...)` binding. All four deferral spellings lose them —
`type M = typeof(require(x))`, `local M = (nil :: any) :: typeof(require(x))`,
`local M: typeof(require(x)) = (nil :: any)`, and
`local M = if false then require(x) else (nil :: any)` — each answering
`TypeError: Unknown type 'M.Spec'` under the pinned analyzer. So deferring those
fifteen means widening their parameters to `any`, which is exactly the argument
checking ADR-0037 exists to have bought, and `tools/check_types.py` now refuses
it: the ceiling arm above runs green in the Luau suite and fails the type check
naming all fifteen lost signatures.

**The route to the remaining 632 KB** is therefore to move the fifteen `export
type Spec` declarations into a module that costs nothing to load, so
`src/init.luau` can keep a direct binding to the TYPES while the implementation
stays deferred. That touches `table.luau` (off-limits this wave),
`virtual_list.luau` and `row_actions.luau` (extraction-locked) plus twelve others,
so it is a scoped follow-up rather than a change to `src/init.luau`.

### SUPERSEDED — the original subset table, and the ranking that came off it

**Every figure below is RETRACTED as a saving.** It is kept, and kept here rather
than in a commit message, for one reason: its RANKING is what found the four
type-free entries and killed the dead candidates, and a ranking survives the
arithmetic error that killed the numbers. Nothing in this block may be quoted as
a saving, a share or a headline; the numbers that mean something are in
"The measurement" above.

*(Restored 2026-08-21, M2-review finding A-M1. `84b38bb`'s message said the table
was "kept and marked SUPERSEDED"; it was deleted instead. This is the claim being
made true rather than a new measurement — no sample was re-taken.)*

**Method as it was run (also superseded).** One subset per PROCESS (`require` is
process-cached, so measuring two subsets in one VM measures the second against the
first's leavings), nine repeats each, median reported, `gcinfo()` sampled the
instant the require returned. Driver: `tools/lune/_probe_t15_mem_all.luau`. The two
defects are named in "Method — and the correction the T15 review forced" above:
no settle before the mark, and subset arithmetic charging each control for the
shared graph `src/init.luau` loads anyway.

| subset | live KB after require | share of root | SUPERSEDED |
|---|---|---|---|
| **`require(Facet)` — the front door** | **2 797** | 100% | bimodal sample; the A/B low-mode median is 2 763 |
| the root MINUS the 19 composite controls | 1 966 | 70.3% | subset arithmetic — the real ceiling is 1 903 |
| …plus `ProgressView` only | 1 998 | 71.4% | subset arithmetic |
| …plus the three Rascal Rally builds (`VirtualList`, `Table`, `ProgressView`) | 2 247 | 80.3% | subset arithmetic |
| …plus `Table` only | 2 291 | 81.9% | subset arithmetic |

The headline read off that table — "the whole saving is 831 KB (29.7%)", and
"550 KB (19.7%)" for the three-composite consumer — is the retracted number. The
A/B on the real file says 228 KB [131..313] shipped and 860 KB [762..860] at the
ceiling.

Inventory, each measured alone with its transitive deps. **Superseded as costs**
(same subset arithmetic), kept as an ORDER — which is the half that was load-
bearing, because it is what said the nineteen controls were the only candidate
worth writing a change for:

| module / group | live KB (SUPERSEDED) |
|---|---|
| `present/presenter` | 1 650 |
| `render/renderer` | 1 018 |
| `blueprint` | 832 |
| `layout/solver` | 638 |
| `core/custom` + `env/environment` | 561 |
| `blueprint_schema` alone | 536 |
| `themes/package` | 417 |
| `themes/snapshot` | 299 |
| `core/custom` alone | 53 |
| `async/resources` | 53 |
| `focus/focus_graph` | 38 |
| `layout/text_metrics` | 27 |
| `client/sensory_profile` | 23 |
| `motion/classes`, `input/actions` | 23 each |
| `input/spatial` | 19 |
| `replication/adapters` | 17 |
| `tokens/tokens` | 14 |
| `themes/standard_icons` | 12 |
| `controls/path_shapes` | 9 |

**The candidate ranking, against what the brief guessed.** The brief listed
candidate seams "in measured-value order (do not assume this order)". The KB
column is superseded; the verdict column is not, and it is what closed six of the
seven candidates:

| candidate | marginal cost ON TOP of the lazy floor (SUPERSEDED) | verdict (STANDS) |
|---|---|---|
| the 19 `Facet.Controls` entries | 831 KB | the only one that pays — re-measured as 860 KB [762..860] at the ceiling |
| `themes/package` | 0 KB | already pulled transitively by the floor |
| `replication/adapters` | 11 KB | noise |
| `input/spatial` | −15 KB (i.e. inside the ±15 KB run-to-run band) | noise |
| `controls/path_shapes` | 7 KB | noise |
| the whole drag/gesture family | 13 KB | noise |
| theme packages beyond neutral | `fantasy_ornate`, the most ornate shipped package, is 68 KB and is NOT in the model at all (per-theme artifacts) | already deferred |

Two structural facts from the same pass, which no re-measurement touches:
`themes/snapshot` cannot be deferred behind a namespace at all — `env/environment`
requires it for `themeMetrics` — and `blueprint_schema` is not a namespace
boundary, because it validates on every `UI.*` call, i.e. a hot path the brief's
own rule excludes.

### The honest caveats

- **Instance-tree memory is engine-owned and unaffected.** Under Rojo every control
  is a `ModuleScript` in the DataModel whose `Source` occupies memory whether or not
  anything requires it. What a deferred require saves is the compiled bytecode, the
  closures and the module-scope tables — not the source text, and not one byte of
  the instance tree.
- **This is a headless host.** Lune's collector, its `require` and its allocation
  behaviour are not Roblox's. The client number is the one a decision should rest
  on, and the instrument for taking it shipped in this wave (below).

### What did ship

The perf lab now carries the client-side instrument end to end. The bootstrap
samples `collectgarbage("count")` before and after `require(Facet)` — the "before"
can only be taken above the require, which is why this could not be added later
from inside the lab — and publishes both through a `heapMarks` host seam. The lab
takes the third mark itself, after the FIRST workload mounts, once: re-taking it on
a warm heap would answer a different question under the same name. A host with no
marks reports `{ measured = false, reason = … }` rather than a zero that would read
as "the require graph is free". Three spec cases, two mutations proved to bite.

`capture-plan.md` §2 tells the controller to read it first and once.

---

## 8. Concerns

1. **A whole control family is outside the measurement surface.** No bench scene
   and no lab workload mounts a `VirtualGrid` or a `RowActions` tray. That is why
   four real RR-5 sites in `virtual_grid.luau` had a value-equal recompute count of
   zero — nothing ran them — and it is why the grid fix had to be measured by a
   spec instead of by a scene. The row-actions half is still unmeasured.
2. **Two measured RR-5 sites are blocked by source-cap locks.**
   `virtual_list.luau:3234` and `table.luau:1968` are the same construct as the two
   that were fixed, they measure as real re-dirty work, and each is one argument
   long. `virtual_list.luau` is 7,813 characters from the write cap with its
   ledger trigger already fired; `table.luau` was off-limits to this wave.
3. **CLOSED IN THIS WAVE.** The public type surface had no mechanical guard at
   all — no analyzer, no gate row — which is how an unverifiable claim about
   `typeof(require(...))` reached a director ruling before anything could test
   it. `luau-lsp` 1.69.0 is pinned in `rokit.toml` and `tools/check_types.py`
   runs inside the `naming-adr-implemented` gate row. It earned its keep on the
   first run: it falsified that idiom, and it is what refuses the remaining
   632 KB until the fifteen spec types move.
4. **The built place carries no stamp a reader can compare.** It was three days
   stale when this wave opened and only a rebuild revealed it. A `Facet_SourceStamp`
   attribute is already read by the capture facts; nothing writes it at build time.
5. **No MicroProfiler dump is in the repository.** The tool's `--selftest` closes
   the decoder half, but the format half — "does a real client still emit this
   shape" — can only be answered by a real dump, and every one this project has
   taken lives outside the tree. `.gitignore`'s existing exception clause
   (irreproducible frozen evidence) would cover one.
6. **`screen-lifecycle-churn` is not a usable trend signal on this host.** It swung
   from 1.23 to 3.57 ms across arms that were provably identical. Any future claim
   about it needs interleaved sampling or a different instrument.
