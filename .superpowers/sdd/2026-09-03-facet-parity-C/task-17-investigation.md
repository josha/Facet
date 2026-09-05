# Task 17 (L3) — the live-only millisecond and a half, attributed

**Verdict, in one line.** The 1.5 ms is **the Luau host, not Facet**: it reproduces in
full with the HEADLESS target inside Studio — zero Instances, zero engine writes, the
same `tests/lib/fake_target` both arms run against — so nothing in `src/` can remove it.
**And the drive found a second, much larger, live-ONLY defect that T9b's instrument
could not see: a settled session pays a synchronous whole-tree COLD re-solve for every
new word it learns — 39.7 ms on `battle_hud L setState`, 77.0 ms on `addItem-damage`,
against 3.7 / 4.0 ms headless.** That one IS Facet's, it is the owner of the
`C stack overflow` at `text_premeasure:484`, and it is booked (ruling A-7) with its
mechanism, its files and its pins below. **No `src/` change is committed by this task.**

---

## 0. Provenance

| | |
|---|---|
| Facet | `facet-parity` @ **`191a7a1a`**, working tree CLEAN at build time (`git status --short` empty) |
| FacetBench | **`c42377a`**, marker stamped to it before the build |
| Place | `rojo build runner/studio/place.project.json --output artifacts/studio-place-t17.rbxl`, opened with `RobloxStudio -localPlaceFile` (pid 21221, killed at the end) |
| Marker read back | `ReplicatedStorage.ui.FacetBench.runner.studio.main:46` = `local MARKER = "c42377a" -- FACETBENCH_MARKER`, equal to the disk line and to the console's `facetbench: boot ready (marker c42377a)` |
| Source read back | mounted `ui.Facet.src.layout.solver` **184,726** chars and `ui.Facet.src.client.text_premeasure` **21,863** chars — byte-equal to `wc -c` on disk. No instrumentation is in the place. |
| Drive route | the DIRECT `require(...)` call inside ONE `execute_luau` in the **Client** datamodel, per `DRIVING.md` §4's "what the relay cannot do". Nothing else was running; the RemoteEvent was never fired. |
| Calibration | **none needed and none used.** This capture is `os.clock()` brackets and Facet's own `profile.setHooks` spans, not a MicroProfiler tick-rate reading, so `FetchGlobalDesc().TickToMsCpu` never enters it. Stated per the brief's Step-1 failure mode: there is no unstated calibration here because there is no calibration at all. |
| Machine | one `lune` at a time. Studio was in Play for arms B/C and STOPPED for arm A. |

**One honest caveat about arm A.** The Lune arm was taken in the shared tree; a
`--noprof` repeat could not be taken because another implementer's in-flight edit left
`src/layout/stack_measure.luau` syntactically broken part-way through
(`syntax error: …stack_measure:633: Expected 'end' (to close 'function' at line 58)`).
The three profiled arm-A runs that DID complete agree to ±0.03 ms and were taken from a
clean tree; the comparison is profiled-vs-profiled throughout, which is the matched one.

---

## 1. The three arms, and why the middle one is the whole answer

The FacetBench facet adapter takes an optional target (`frameworks/facet/adapter.luau:240`,
`FacetAdapter.mount(spec, target)`): with a target it builds the PRODUCTION
`screen_target` + `roblox_env.bind`; without one it builds `Facet/tests/lib/fake_target`
— **the same object the Lune arm uses**, with a fixed 1280x720 viewport. So the middle
arm exists:

| arm | host | render target | what it isolates |
|---|---|---|---|
| **A** | Lune | `fake_target` | the headless baseline |
| **B** | **Roblox Studio (Play, client VM)** | **`fake_target`** | **the HOST, and nothing else** |
| **C** | Roblox Studio (Play, client VM) | `screen_target` under a rendering `ScreenGui` | the adapter + the engine |

`B − A` is the host. `C − B` is everything the engine and the production adapter add.
Arm B is not a fixture: it is the identical Luau, identical node counts, identical
allocation, driven by the identical script through the identical adapter entry point.

### The numbers (p50 ms, `battle_hud` **L**, 5,127 layout nodes)

| class | **A** Lune | **B** Studio + fake | **C** Studio + live | **B−A** (host) | **C−B** (engine/adapter) |
|---|---:|---:|---:|---:|---:|
| `updateItem-hp` | **2.534 / 2.495 / 2.550** | **3.522** | **3.477** | **+0.99** | **−0.05 (zero)** |
| `setState` | 2.268 / 2.384 / 2.286 | 3.733 | **39.676** | +1.42 | **+35.94** |
| `updateItem-facing` | 2.562 / 2.776 / 2.719 | 3.760 | 4.848 | +1.07 | +1.09 |
| `addItem-damage` | 2.830 / 2.687 / 3.006 | 3.994 | **76.971** | +1.16 | **+72.98** |
| `noop` (the control) | 0.003 | 0.003 | 0.004 | **+0.000** | +0.001 |

Arm A is three independent `lune run tools/profile/attr battle_hud L 1` runs. Arm B was
also taken a second time without the profile hooks (`ARM=B2`, 300 samples): hp 3.798,
setState 3.740, facing 4.277, addItem 4.546 — the hooks cost nothing measurable, and the
host gap is if anything larger without them.

---

## 2. Attribution of T9b's 1.5 ms: **the host, to within 0.02 ms**

T9b measured `battle_hud L updateItem-hp` at 1.824 Lune / 3.382 live (`09d2dfcc`) and
`setState` at 1.927 / 3.426 with **zero engine writes**. At HEAD the same surplus is
**+0.95 ms** on hp (2.53 → 3.48) — T13 moved both baselines, so the surplus is smaller in
absolute terms and the RATIO is what carries across (1.85x at `09d2dfcc`, 1.37x at HEAD).

**All of it is `B − A`.** The per-span table, exclusive, one `updateItem-hp` step:

| span (exclusive) | **A** Lune | **B** Studio + fake | **C** Studio + live | B−A | mechanism | side |
|---|---:|---:|---:|---:|---|---|
| `Facet/measure` | 1.203 | 1.511 | 1.477 | **+0.31** | the same 1,151 `measure` calls, 1.26x slower | host |
| `Facet/arrange` | 0.993 | 1.415 | 1.412 | **+0.42** | the same per-child `margins`/`desired`/`childRect` loops, 1.43x slower | host |
| `Facet/commit` | 0.159 | 0.224 | 0.226 | +0.07 | the same 1,134 `skip` questions | host |
| `Facet/react` + `dirtyScan` + `dirtyClosure` + `lane` | 0.010 | 0.011 | 0.011 | +0.00 | — | — |
| outside every span (`toLayoutNode` 0.202, `cw.harvest` 0.131, `rectPass.apply` 0.010, six commit walks) | 0.185 | 0.361 | 0.351 | **+0.18** | the same build + harvest walk | host |
| **step p50** | **2.550** | **3.522** | **3.477** | **+0.97** | | |

**Unattributed remainder: 0.00 ms.** Every millisecond of the surplus sits inside a span
that runs identically in both arms, with identical counters (`lastMeasureCalls` 1,151 vs
1,151, `lastCommitScans` 1,134 vs 1,134, `lastLayoutNodes` 5,124 vs 5,124, `lastMeasured`
9 vs 9) and **identical allocation** (`gcKb` 1,108.9 Lune vs 1,107 Studio). Same bytes,
same calls, same walk — the host simply charges ~1.4x for them.

**Three independent facts say this is per-node work and not a fixed cost:**

1. **`noop` is 0.003 ms in BOTH hosts.** The fixed per-tick path — `dirtyScan`, `lane`,
   the stats publish — costs the same in Lune and in Studio to the microsecond. This is
   the same shape T9b §3 found from the S/M/L fit (live intercept 0.129 vs Lune 0.124,
   within 4 %, while the marginal was 1.95x) and it is now measured directly rather than
   extrapolated from three points.
2. **The surplus is distributed in proportion to each span's own size** (measure ×1.26,
   arrange ×1.43, commit ×1.41, build+harvest ×1.95) rather than concentrated in one.
   An added ACTIVITY lands in one place; a slower host multiplies everything.
3. **`gcKb` is identical.** Facet allocates 1,109 KB per hp tick on both hosts. What
   differs is what a byte costs — which is the one term this capture cannot decompose
   further (interpreter speed vs collector cost under a multi-hundred-megabyte engine
   heap). Named as the open question, not as a claim.

**Verdict: INHERENT. `+0.95 ms` on `battle_hud L updateItem-hp` at `191a7a1a` is the
price of the Roblox Luau host over Lune for the identical work. No `src/` change removes
it.** The campaign's report must quote it as such.

### The standing rule this produces

> **A headless lever's live gain is unknown until the live/headless ratio for its class
> is attributed, and the attribution needs a THIRD arm — the headless target inside the
> live host.** This campaign predicted "about 2x" from a two-point scaling fit and that
> was the weakest number in the whole report. The third arm cost one `execute_luau` call
> and turned a prediction into a decomposition: on `updateItem-hp` the ratio is **1.37x
> and entirely the host** (so every millisecond T13–T16 remove is worth 1.37x live, not
> 2x, and nothing is hiding under it); on `setState` and `addItem-damage` the same
> prediction was off by a factor of **ten to twenty in the other direction**, and only
> the third arm could tell those two cases apart.

---

## 3. The second finding, which is the larger one: a learned word costs a cold whole-tree re-solve

### 3.1 What was measured

Arm C, `battle_hud L`, session **settled** (the probe waits for `controller.textPending()`
to fall before it samples — i.e. the state a shipped game is in from ~0.66 s onward):

```
-- setState n=20 p50=39.676ms gcKb=2165
   counts: st.lastMeasureCalls=10257 st.lastMeasured=10257 st.lastArranged=4
           st.solves=2 st.textMeasureBatches=1 st.engineWrites=4
-- addItem-damage n=30 p50=76.971ms gcKb=193
   counts: st.lastMeasureCalls=14257 st.lastMeasured=14257 st.lastArranged=5127
           st.solves=2 st.textMeasureBatches=1 st.engineWrites=103
```

Against arm B (same step, same code, headless target):

```
-- setState n=20 p50=3.733ms   counts: st.lastMeasureCalls=1157 st.lastMeasured=6  st.solves=1 st.textMeasureBatches=1
-- addItem-damage n=30 p50=3.994ms counts: st.lastMeasureCalls=1244 st.lastMeasured=3 st.solves=1 st.textMeasureBatches=1
```

`lastMeasured == lastMeasureCalls` is the signature: **every measure is a MISS**. The
memo store is not stale, it is *empty* — a second, fully COLD solve of the whole tree,
plus a whole-tree arrange on `addItem-damage` (5,127 arranged against 5).

A dedicated probe isolated one step (probe D, one `addItem-damage` on a settled session):

```
MOUNT: spawns=2 sync=0 async=2 maxNestDepth=2 maxLuaStack=1
SETTLED one addItem-damage: 48.296ms spawns=1 sync=1 solves=2 feedbackSolves=0
   measureCalls=14229 measured=14229 arranged=5113 textBatches=1 corrections=0
TOTALS: spawns=14 sync=11 async=3 maxNestDepth=3
```

`sync=1` on that step is the load-bearing observation: `text_premeasure.spawn`'s body
**completed before `task.spawn` returned** — the whole answer chain ran on the caller's
stack, inside the step.

### 3.2 The mechanism, end to end, with citations

1. A step introduces a word the estimator cannot size exactly (`-437`, `73`, `218`).
   The renderer's premeasure round asks for it at the end of the solve
   (`src/render/premeasure_round.luau:74-91`).
2. `screen_target` routes that to `text_premeasure.measure`
   (`src/client/text_premeasure.luau:477`), which calls
   **`text_premeasure.spawn(function() … end)` at `:484`**.
3. `spawn` is `task.spawn` (`:319-321`), which runs the body **synchronously until its
   first yield**. On a **settled** session the body's first branch is taken
   (`:486-489`): `deliver(measureBatch(requests))` — and `measureBatch`'s
   `GetTextBoundsAsync` **does not yield** once the font is loaded. Measured: `sync=1`.
   So there is no yield at all and the whole chain below runs inline.
4. `deliver` → the renderer's `done` (`premeasure_round.luau:91-157`). A word never
   measured before has `previous == nil`, so `learned` is true by construction.
5. `learned` ⇒ `env:set("textMeasureEpoch", …)` and, if that write did not itself solve,
   `solveAndApply()` (`premeasure_round.luau:149-155`).
6. And the re-solve is COLD, not incremental, because **`text_metrics.setMeasured` bumps
   a PROCESS-GLOBAL epoch** (`src/layout/text_metrics.luau:202,242`) which the renderer
   folds into `measureStamp` (`src/render/renderer.luau:1986`,
   `.. "|{measureScale}|{prefOffset}|{text_metrics.epoch()}"`), and `measureStamp` is
   axis 3 of the measure serve — *"a stamp that moved drops BOTH slots at once"*
   (`solver.luau:1465-1470`, `:1612`) and of the container memo
   (`stack_measure.luau:136-141`). One learned word therefore invalidates the measure
   memo of **every node of every attached surface**.

**So: one new word ⇒ one synchronous whole-tree cold re-solve, charged to whatever step
happened to introduce it.** 36–73 ms on `battle_hud L`. `war_room_inventory` and any
scoreboard, damage number, timer or currency readout is the same shape.

### 3.3 This is also the owner of the `C stack overflow`

T9b's first drive printed
`C stack overflow (when calling anonymous function on line 484 in ReplicatedStorage.ui.Facet.src.client.text_premeasure)`
and then `Script timeout`. `:484` is the `spawn` callsite above, and step 3 is why it is
a stack frame rather than a queue entry: **the answer chain is synchronous, so
`solveAndApply` (5) re-enters `premeasure_round.request`, which calls `measure`, which
calls `spawn` at `:484` again — one C frame deeper.** The nesting was measured, not
inferred: **`maxNestDepth=3`** on an ordinary `battle_hud L` mount+drive, with three
`spawn` bodies live on one stack.

**The recursion is Facet's, and the recursing cycle is named:**
`text_premeasure.measure` (`:477`) → `spawn` (`:484`) → `deliver` (`:479`) →
`premeasure_round`'s `done` (`:91`) → `solveAndApply` (`:154`) →
`renderer` solve → `premeasure_round.request` (`:74`) → `adapter.measureTextWidths`
(`:91`) → `text_premeasure.measure` (`:477`). There is no depth bound anywhere on that
cycle. `textInFlight` (`premeasure_round.luau:62`) bounds it for one surface's one
vocabulary — the same word cannot be asked twice — but it does NOT bound a cycle in
which each re-solve discovers a *different* new word, and it is per-surface, so **two
attached surfaces can drive each other**: surface A learns a word, the global epoch
moves, surface B re-solves cold, B discovers a word of its own, and the cycle closes.
That is exactly the configuration T9b's overflow occurred in — **two workloads in one
`main.run`** — and it is why one workload never reproduced it.

I did not spend a further live drive re-triggering the overflow: the depth counter is
the stronger evidence (an overflow says "too deep", a depth of 3 on an unremarkable
drive says *why*), and the console line above is the artifact.

---

## 4. STOP, and the booking (ruling A-7)

Both findings hit a STOP condition and neither produces a `src/` change here.

* **Finding 1** — *the surplus is in the host, which Facet cannot avoid.* Named inherent
  with its number: **+0.95 ms on `battle_hud L updateItem-hp` at `191a7a1a`, 1.37x, 0.00
  unattributed.** STOP.
* **Finding 2** — *a Facet-side mechanism found.* The proposed fix is written below and
  **not built**, per the brief's step 4. It would also breach three of the four STOP
  conditions if attempted here: it touches **two** `src/` modules at minimum
  (`premeasure_round.luau` + one of `text_premeasure.luau` / `text_metrics.luau`), it
  changes the settle/delivery timing that `tests/text_settle.spec.luau` and RR's
  `tests/facet_text_settle_contract.spec.luau` pin, and the whole-tree-invalidation half
  is a change to the measure-stamp contract. **It is a RED-TEAM item for Task 10, and it
  is a correctness defect (an unbounded re-entry with a live console overflow) before it
  is a millisecond.**

### The proposed fix, in the two halves it actually has

**Half A — break the synchronous re-entry (the correctness half, and the cheap one).**
The premeasure answer must not run on the requesting solve's stack. `text_premeasure`
already owns the seam: make the settled branch defer one resumption point instead of
delivering inline —

* **Mechanism.** In `text_premeasure.measure`'s settled branch
  (`src/client/text_premeasure.luau:486-489`), yield once before `deliver` (a
  `text_premeasure.wait(0)` through the existing fakeable `wait` seam, so the headless
  suite still drives it in virtual time), so `task.spawn` returns to the caller before
  any `done` runs. The whole `deliver → done → solveAndApply` chain then starts from the
  scheduler, at depth 0, exactly as the boot-window branch already does after
  `awaitSettled()`. Belt and braces: a re-entry depth counter in
  `premeasure_round.request` that refuses to start a round while one is delivering, and
  publishes the refusal as a counter.
* **Files.** `src/client/text_premeasure.luau` (the one-line defer) **or**
  `src/render/premeasure_round.luau` (the depth guard) — one of the two, not both, is
  enough for the overflow; the guard is the one that also covers the two-surface cycle.
* **The counter that proves it.** A new `textRoundDepth` (max re-entry depth) on
  `render_stats`, pinned `== 1`, plus the existing `textMeasureBatches`. Probe D's
  instrument is the live oracle: `maxNestDepth` must read **1**, not 3.
* **The headless pin that would catch it.** `tests/lib/fake_target` already holds
  batches and has `deliverTextWidths`; a spec that delivers a batch whose re-solve
  requests a SECOND new word, with the fake target answering that one inline too, and
  asserts the second `measureTextWidths` call is not on the first one's stack (a depth
  counter, or `textRoundDepth == 1`). **This is reproducible headless** — it needs no
  real `GetTextBoundsAsync`, only a fake target that answers synchronously, which is
  exactly what the live one does once settled.

**Half B — stop invalidating the whole tree for one word (the millisecond half).**
`text_metrics.epoch()` is a process-global generation folded into `measureStamp`
(`renderer.luau:1986`), so the granularity of "a text metric changed" is currently
"every node of every surface". The honest narrowing is per-WORD or per-(font,size)
invalidation: a node's measure only depends on the words it contains. That is a real
design change with a real correctness argument to make (`text_metrics.luau:170-200`
states why the epoch is global and cross-surface, and that argument is sound for
CORRECTNESS — it is the granularity that is the cost), and it is not a Task-17 edit.

* **The number it is worth.** On `battle_hud L`, 50 of 200 sampled steps pay it:
  20 `setState` at 39.7 ms and 30 `addItem-damage` at 77.0 ms against 3.7 / 4.0 headless
  — **~2.9 seconds of the 200-step window, against ~0.7 s if they cost what the other
  classes cost.** It is larger than every lever T12–T16 combined, and it is invisible to
  every headless instrument in this campaign.

### What T9b's live matrix could not see, and why

T9b drove without waiting for the text settle. In the boot window
(`text_premeasure.luau:491-511`) the batch delivers `early` with `final = false` and then
**`awaitSettled()` — which yields** — so the corrections land asynchronously, on some
later frame, and never inside a measured step. T9b therefore read `setState` at 3.426 ms
live: the *un-settled* cost, which is arm B's number plus the host, and which is not the
cost a shipped game pays. **The settled steady state is the one to measure, and a live
drive that does not wait for `controller.textPending()` to fall is measuring the boot
window.** That belongs in `DRIVING.md`'s trap list.

---

## 5. Hygiene

One place open at a time (`studio-place-t17.rbxl`, pid 21221, `kill -9`'d; the unrelated
`t9b-place.rbxl` window was not mine and was left alone). Play stopped before the kill.
No probe script was ever parented into the place — every arm ran through `execute_luau`
and every arm unmounts its handle and destroys its target folder on the way out.
`artifacts/` is gitignored; no `.rbxl` is committed. The only tracked file this task
changes outside its own documents is FacetBench's `runner/studio/main.luau` marker line,
stamped to `c42377a` per `DRIVING.md` §1.
