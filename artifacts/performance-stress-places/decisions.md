# Performance stress places — decision packets (roadmap Step 9)

**Date:** 2026-08-04. Each packet records a decision the plans did not resolve, the
evidence behind it, and what would change it.

---

## PLN-1 — One place, not two

**Question the plan poses.** "Add another place only if a measured isolation problem
requires it — for example, if a minimal native reference cannot be kept dormant
without affecting the LuauUI capture."

**Decision: one place, `examples/places/LuauUI-PerformanceLab.rbxl`.**

**Measured.** The native reference is not merely dormant, it is **absent** until
mounted: `native_list.mount` is the only thing that creates its `ScreenGui`, and
`perf_lab.mount` refuses a second implementation outright. The live census confirms
the isolation rather than assuming it — with the LuauUI list mounted, PlayerGui's
foreign roots are `["Freecam"]` and foreign GuiObjects are **0**; with the reference
mounted, LuauUI-owned GuiObjects are **0** and the reference's 119 objects are
counted as foreign. There is no dormant tree to affect a capture.

Keeping one place also keeps engine, content, rendering settings and capture
workflow identical across the two implementations, which is the comparison's whole
value. A second place would reintroduce exactly the variable it was meant to remove.

**What would change this.** If a future workload needed a materially different
place configuration (different lighting, streaming, or a server topology), it gets
its own place with a single documented purpose — and captures from the two are never
compared as one workload.

---

## PLN-2 — The MicroProfiler scope set is closed at nine, and internal

**Decision.** `src/core/profile.luau` declares nine phases — `mutate`, `react`,
`measure`, `arrange`, `commit`, `resource`, `mount`, `scenario`, `reset` — with a
`MAX_SCOPES = 12` ceiling, and `span` **refuses** any name outside the set.

**Why a closed set.** The plan forbids a label per row, key or node, and a comment
saying so is not a mechanism. The refusal makes the rule fire at the call site, and
a headless case proves the emitted label count does not scale with row count (a
4-row tree and a 40-row tree open the same number of scopes).

**Why these nine.** Each is a phase whose regression has a *different fix*. `measure`
and `arrange` are split because a measure regression is text metrics and intrinsic
sizing while an arrange regression is distribution — and that split is what named
the L-4 cause. `mount` is split from `commit` because Instance churn is a
keying/virtualization problem and property writes are a diff problem. `mutate` is
split from `react` so "the game wrote 400 signals" is distinguishable from "the
framework walked the graph".

**What is deliberately NOT split.** The adapter commit is one scope for the whole
pass — visibility, hit rects, rects, scroll regions, z-order and the text follow-up
— because the question a capture asks is "is the framework's output cheap relative
to its solve", and eight sibling bars answer it worse than one.

**Why internal rather than a public export.** A profiling wrapper is a plausible
public utility, but exporting it drags in a surface-ledger row, an api.md entry and a
constitution classification — Step 7's territory, and adjacent work here. The lab
reaches it by instance path through a **named exemption** in
`tools/lune/check_boundary.luau`, the same mechanism four other in-repo harness
reaches already use. The point is that the driver's scopes and the framework's come
from one implementation and cannot disagree about naming or balance.

**Balance is proved, not asserted.** Lune has no `debug.profilebegin`, so the
instrumented branch would never execute under the suite. `profile.setHooks` installs
a recording pair so the real path runs against an observable sink; the spec proves
balance on normal return, on an error, on a non-string error, and on a nested throw,
and a mutation that skips the close reddens exactly those three cases. Live in
Studio: 2 409 opens, 2 409 closes, max depth 3.

---

## PLN-3 — What makes a capture row inadmissible

**Decision.** `examples/performance/lab/capture.luau` owns the row schema and the
refusal. A row is inadmissible if it is missing any identity, workload, condition,
method or result field — and **`"unknown"` counts as missing**.

**Why that last rule matters.** The first version defaulted every unavailable
condition to `"unknown"`, which made every row admissible and none comparable. The
rule now distinguishes three things: a value (fine), `"n/a"` or `"not recorded"` (an
explicit declaration that the quantity does not exist for this class or was
deliberately not taken — fine), and `"unknown"` (the answer of a harness that did not
look — refused).

**It caught a real hole immediately.** The first Studio export was refused with
`missing conditions.graphicsQualityLevel`: the host read the level through
`settings()`, a plugin global that is `nil` in a LocalScript. The host now reads
`UserGameSettings`. Had the rule been lenient, every capture in this stage would have
carried a silent `"unknown"` quality level.

**Class laundering.** The evidence class is stamped by the **host**, not by the
operator — a Studio session mints `studio`, a retail client mints `desktop-retail`,
and the device-class fields stay `nil` in Studio *on purpose* so a relabelled Studio
row cannot look like a device row. `capture.problems` additionally refuses a
device-class row that carries a `studioVersion`, because a retail client has none.

---

## PLN-4 — Two shipped ownership shapes for composite controls

**Observed, not decided here.** `newAsyncImage` accepts a `scope` and owns itself
into it. `newStepper` (and `newSlider`) take no `scope` key and instead return a
`dispose`. Both are legitimate; a consumer writing a virtualized cell has to know
which shape each control uses, and assuming the wrong one leaks a control scope per
materialized row — measured at 17 078 memos and 4 278 scopes after 400 scroll steps
(optimization log L-2).

**Decision for this stage: fix the caller, not the API.** The row owns the returned
handle in the cell scope, and a durable regression bounds reactive growth across
scrolling. Unifying the two shapes is a public-surface change and belongs to the API
consistency stage (Step 7), which owns the surface ledger and the deprecation path.

**Evidence for whoever takes it up:** a per-row control is the case where the
difference bites, virtualized lists are the case where per-row controls are normal,
and the failure is silent — nothing warns, the suite stays green, and only a counter
census over a long scroll shows it.

---

## PLN-5 — Instance recycling is an architecture decision, not a perf tweak

**Measured gap.** On the identical dataset, pitch, viewport and interaction, with
the overlay dismissed: LuauUI's dense scroll runs at p50 **3.92–4.22 ms** and the
matched raw-Roblox reference at p50 **1.01–1.03 ms** — about **3.9×** at the shipped source (**4.7×** before the solver memo fix) — and LuauUI
creates **23.6 GuiObjects per row** against the reference's **9.2**. Under the seek
workload the difference is almost entirely `LuauUI/mount`.

**Why the gap exists.** The reference recycles a fixed pool of row frames and
repaints them. LuauUI's keyed `ForEach` creates a subtree when a key enters the
window and destroys it when the key leaves — which is what makes mount identity,
per-row scope lifetime, focus survival and repaint-vs-remount claims *true*, and
several shipped gates assert exactly those properties.

**Decision: do not change it in this stage.** Recycling would rewrite the identity
semantics other gates pin, which is not "the smallest framework change that
addresses it without weakening behavior". It is escalated with numbers rather than
attempted.

**What a decision would need.** A design that keeps mount identity observable
(a recycled node is a *different* node to a consumer holding a path), a story for
per-row scopes and async cancellation, and a measurement that the saving survives
the bookkeeping. The reference's capability ledger is the honest denominator: it has
no focus graph, no theme authority, no async resource lifecycle, no preferred-text
reflow or disclosure, no adaptive composition or safe areas, and no hit-target floor.
Some of the 4.7× is buying those.

---

## PLN-6 — `UI.Text` draws embedded newlines and does not measure them

**Found live** driving the lab's own counter block: a six-line string joined with
`\n` solved to an `879 x 29` box, drew six lines into it, and reported
`truncated = false`. The solver's text facts say `naturalLines = 1`.

**Decision: record and route, do not fix here.** The measure path is Step 8.5
territory — exact-once preferred-text offsets, the premeasure cache and its
boot-window corrections, the truncation/disclosure ladder — pinned by a large gated
suite. Teaching `naturalLines` about `\n` is a small change with a wide blast radius
(every reserved text box, both reference themes, four preference values), and
slipping it into a performance stage is how a text regression ships.

The reproduction is three lines and needs no engine; it is in
`docs/lessons/embedded-newlines-measure-as-one-line.md` together with the
workaround the lab now uses (one `UI.Text` per line).

---

## PLN-7 — Why PL-P3 exists instead of PL-1 quietly covering it

**The gap, stated plainly.** Every behavior row in this stage was driven live through
the real adapter — but through the lab's **sources injected into an open Studio
place**, not by opening the emitted `.rbxl` file. Nine source stamps, six Play
sessions, all real; none of them was `File → Open from File`.

**Why it was done that way.** The lab's sources changed nine times during the stage
(two instrument defects, one workload versioning, one framework fix, three usability
fixes). Rebuilding and reopening a place file for each would have been slower and no
more truthful about the *behavior* — the running code was byte-identical to the
built sources every time, and the source stamp on every capture proves which state
each session ran.

**Why it is not enough on its own.** What injection cannot prove is the **Rojo
mapping**: that `examples/performance.project.json` puts the modules where the
bootstrap looks for them in a real build. `tools/check_perf_place.py` inspects the
built tree and asserts all sixteen required instances, their classes, the five
version markers and that the scenario runner is byte-identical to the gallery's — so
a dropped or misplaced module fails the gate. But a tree inspection is E1; booting
the file is E3, and only a person can perform `File → Open from File`.

**Decision.** PL-1 claims exactly what is proven — the build is complete, correct and
publish-safe — and the boot of the emitted file is its own row, **PL-P3**,
`PENDING_HUMAN`, with a one-screen checklist in the review packet. Folding it into
PL-1 would have been the easy row passing the hard one, which the execution contract
forbids by name.

**Cost of closing it:** about two minutes. Open the file, press Play, confirm the two
console lines, tap through the selector, `reset`, `export`.

---

## PLN-8 — What the four fresh-context reviews changed (dispositions)

The reviews are in `reviews/`. This packet records what was **acted on**, because a
finding with no disposition is a finding nobody answered.

### Fixed in this stage

| Finding | What was wrong | Fix |
|---|---|---|
| **architecture BLOCKER-1** | The per-solve `measure` memo cached only `(w, h)`, silently turning "last write wins" into "first measure per box wins" for `ctx.compact` and `ctx.textFacts`. Differential fuzz over 800 seeded trees: geometry byte-identical (`rectDiff = 0`), `compact` flipped on 3 trees, `textFacts` on 12 — **including `truncated` true → false**, which gates full-value disclosure and the reveal. A cut label losing its accessible full value, with the geometry unchanged. | The cache entry now carries the verdicts and **replays** them on a hit (`solver.luau`). Re-running the reviewer's own fuzz against the fix: `rectDiff=0 textFactsDiff=0 compactDiff=0`. Durable regression in `tests/measure_memo.spec.luau` built from the review's auto-shrunk trees (seeds 132/612/91), mutation-proved: removing the replay reddens the 612 and 91 cases. |
| **platform MAJOR-2** | `profile.enabled` defaulted to `true`, so on the engine every LuauUI phase ran under a `pcall` and re-raised at level 0 — truncating tracebacks in production, permanently, for an instrument almost nobody reads. Lune could never catch it (`active` is false there). | Scopes now ship **off**; the lab opts in at boot. Pinned by a case asserting the default. |
| **platform MAJOR-1** | `span` guards return and error but not **yields**, and the lab wrapped each pass — 60 Heartbeat waits — in one open `LuauUI/scenario` scope. The counters count Lua call sites, so `balanced` read true regardless. | The pass wrapper no longer opens a scope; the per-frame scope in the bootstrap stays because it does not yield. The no-yield rule is now rule 2 in `src/core/profile.luau`. |
| **platform MAJOR-4/5, MINOR-5** | The guide's mobile-MicroProfiler procedure was wrong in three places: it invented a developer-console tab, omitted that the phone serves a **web UI** you browse from another machine on the same network, and named `.gprx` instead of the `microprofile-<date>-<time>.html` that **Save to file** downloads. | §12.5 rewritten against the first-party doc, including the 30-frame default and the `/<n>` URL suffix. |
| **platform MAJOR-6** | "No private asset" was asserted for the whole place; the doctor cannot establish the public status of the ornate package's 34 asset ids or `standard_icons`' eleven. | The guide now states exactly what the doctor proves and what it does not, and which workload is affected. `rbxthumb` avatar headshots were separately **confirmed** to need no upload or permission. |

### Fixed after the reactive-runtime review landed

| Finding | What was wrong | Fix |
|---|---|---|
| **reactive MAJOR RR-9** | `rebuildDataset` disposed every per-row value/toggle signal **while the rows were still mounted**. `UI.ForEach` does not rebuild a row whose key is unchanged, and the ids (`r{i}`) are stable across a seed or content change — so mounted cells were left holding disposed signals. Measured: 60 rows mounted, then the declared `localeSwap` pass, and 18 signals were disposed with **zero** cells rebuilt. Second-order: `localeSwap` therefore swapped no visible text and timed a no-op while reporting a number. | `rebuildDataset` unmounts first and remounts after, so the fresh dataset builds fresh cells. Verified: signals stay at 92 across the swap and the list stays mounted. |
| **(found while confirming RR-9)** | `raiseOverlay` rebuilt the overlay blueprint on every mount, and `overlayLib.build` allocates one memo per counter line — **six leaked memos per mount**. Signals and scopes stayed flat while memos climbed 112 → 130 → 148 → 166 → 184 across four dataset swaps. The Studio soak missed it because that run had clean capture **on**, where `raiseOverlay` early-returns: a leak hiding behind the one mode that never exercises it. | The blueprint is built once and re-presented. Verified flat at 106 memos across four cycles. |
| **reactive RR-1 / RR-2** | A throwing profiler hook escaped `profile.span` before its accounting could unwind — leaving `depth` at 1 and `opens > closes` forever, and one layer up escaping `flush`'s react span before `flushing = false` could run, **silently killing the core for the rest of the session with nothing recorded**. Not reachable with scopes off (the new default), but live in exactly the configuration the lab ships. | Both hooks are `pcall`ed: a broken instrument may lose its own measurement, it may not take the framework down with it. Pinned by a case that installs a throwing pair and asserts the body still ran and the counters balanced. |
| **reactive RR-11** | The "does NOT grow the reactive core" regression bounded memos and scopes and said nothing about **signals** — the other half of the same live defect (a Studio reset once left 488 undisposed signals). | The case now bounds signal growth too, against the rule (two per row visited) rather than a flat number. |

### Recorded, not fixed — with the reason

| Finding | Disposition |
|---|---|
| **platform MAJOR-3** — a LibMP log iterator configured with `TimerIds` returns zero exits, because a LEAVE record carries no timer token; identity comes from the thread's scope stack. Any duration from a filtered iterator is unsound. | Not a defect in this stage: every number here came from the **unfiltered** iterator with a Luau-side filter (the filtered attempt returned zero and was abandoned before any number was taken). The guide says so explicitly. The upstream documentation gap is worth an issue against `Roblox/libmp`; not this stage's to file. |
| **platform MAJOR-7** — the native reference early-returns when the window's start index has not moved, so at 40px/frame over a 60px pitch roughly one frame in three costs ~0ms, while LuauUI calls `presenter.refresh()` unconditionally. The 4.7× compares distributions of slightly different work. | Recorded in PLN-5 rather than "fixed": making the reference refresh unconditionally would make it a worse floor (a real hand-rolled list *would* early-return). The direction of the gap is not in question — the p50 difference is 4.6× and the per-row Instance count 2.6× — but the ratio should be read as "about 4–5×", not a precise multiple. |
| **platform MAJOR-8** — L-1's stated cause was wrong. Under the default `SignalBehavior.Deferred`, `GetPropertyChangedSignal` fires at the next resumption point, normally later in the **same** frame; the genuine frame-boundary effect is `CanvasPosition` clamping against `CanvasSize - AbsoluteWindowSize`. | The behaviour and the fix are unchanged (the Heartbeat wait is still required and still measured). The optimization log's L-1 now states the corrected cause, so the next stage does not reason from the wrong one. |
| **architecture MINOR-8 / platform MINOR-1** — the memo's cost was never measured on trees that do not benefit. | **This became a real gate failure and was fixed, not merely recorded.** A flat 60-node tree cost +8%, and `textinput-typing-storm` crossed the bench's 1.5x regression rule — worse in 6 of 6 interleaved A/B pairs. The memo is now scoped to trees that actually contain a scroll node (`ctx.hasScroll`), which removes the cost where there is no saving and leaves the beneficiary untouched (`LuauUI/arrange` 1.199 ms, `lab-dense-scroll` −11%, both interleaved). See optimization log **L-6**. |
| **reactive RR-3/4/5/6/7/14/15** — traceback frames erased by the level-0 re-raise; instrumented vs un-instrumented error semantics differ; `LuauUI/react` is not disjoint from `measure`/`arrange`/`commit` when a solve runs from inside an observer (so summing `byScope` double-counts); a yielding transaction body would leave `mutate` open; the resource wrapper allocates a closure per completion; the memo de-duplicates diagnostics; the replay list enumerates four channels by hand and `regionForm` is a fifth that is arrange-only today. | All real, none load-bearing. RR-5 is the important one for a **reader**: LuauUI scope times are inclusive and can nest, so compare exclusive times or a single phase, never a sum of `byScope`. That is now stated in the guide's profiling section. The rest are carried forward. |
| **architecture MINOR-2/4/5/6, MINOR-10/11** — `span`'s pcall reshapes tracebacks while active; `profile` is a process-global singleton; `setHooks` has no provenance marker; `ctx.host` is an unvalidated bag; the boundary exemption is keyed on a filename and covers all of `examples/`. | All real, none load-bearing for this stage's claims, and each is a public-surface or tooling decision rather than a performance one. MAJOR-2's fix (off by default) already removes the production half of the traceback concern. Carried forward as named follow-ups rather than changed under a performance goal. |
| **architecture MINOR-3** — the memo's safety comment was factually wrong about `ctx.diagnostics` being a keyed write. | Comment corrected in place; the diagnostic **set** is identical over 800 trees and only duplicate counts shrink, which is recorded rather than restored. |

---

## PLN-9 — What the phase-gate review found, and what changed

The phase-gate reviewer ran the gate, tried thirteen falsification mutations against
the checks, and audited every PL row against the artifacts. **Eleven of thirteen
mutations bit**, including all three rules of `check_perf_captures.py`. What it caught
that mattered:

| Finding | What was wrong | Fix |
|---|---|---|
| **F-2 (MAJOR)** | `src/core/profile.luau` declares **nine** scopes; the Studio artifact recorded **eight**, claimed "the eight names are the whole closed set", and `check_perf_gate_evidence.py` hard-asserted `len(timers) == 8`. Appending the truthful ninth would have **reddened** the gate. `LuauUI/reset` was simply never exercised in that capture — a scope enters the timer table only once it has run. | Re-captured while driving a `reset`: **all nine** appear. The check now reads the declared set **out of the source** and requires every declared scope to have been observed, so neither a missing scope nor an undeclared one can pass. Mutation-tested. |
| **F-5** | `check_perf_place.py` hardcoded `/Users/josha/.rokit/bin` — a developer path inside the tool whose job is refusing places that contain developer paths. | Resolved from `$HOME` and filtered to directories that exist. |
| **F-6** | The "runner reused, not forked" check compared the built runner's source against the repo file it was built from — both sides are the same file, so it could not fail. A mutation confirmed it. | The assertion moved to the **project mapping** (`$path == "gallery/scenarios/runner.luau"`), plus a check that no forked copy exists beside it. Mutation-tested: pointing the project elsewhere reddens it. |
| **F-7** | Admissibility refused the exact token `"unknown"`, so `"uncapped/unknown"` passed. | Changed to a containment test in both the Luau and the Python side — which **immediately caught a real non-answer**: every capture row carried `frameTarget = "uncapped/unknown"`. The frame target is not readable from a LocalScript, so it is now declared, defaulting to the honest `"not recorded"`, and the six stored rows were relabelled with a visible note rather than silently. |
| **F-8** | The memo regression spec implied all four cases bite; only two do. | The file now says which two bite and why the third is corroboration only. A test file that overstates its own coverage is how the can't-ever-fail class survives. |
| **F-3** | The optimization log claimed "every other scene's budget is byte-identical"; re-serialising moved nine float fields at ~1e-16. | Corrected to the claim that was actually checked: no budget changed in value, and none was loosened. |
| **F-1 (BLOCKER at the time)** | The gate was red on `prior-gates-unregressed` (the sweep had not been run at final source) and `fresh-context-reviews` (two of four reports missing — one reviewer had no Write tool, one had not been prompted to write). | The sweep was run; the missing reports were written. The `rascalrally-consumer` red was a wording mismatch between the ledger and its own grep, aligned. |

**F-9** duplicated an architecture MINOR already corrected in place (the memo's safety
comment about `ctx.diagnostics`), and **F-4** was the missing-reports symptom of F-1.

**The observation worth keeping.** The reviewer's most valuable finding, F-2, was a gate
check that had **frozen a wrong fact into place** — it would have refused the truth. A
check that asserts a magic number instead of reading the source is not a weaker check;
it is a check pointing the wrong way.
