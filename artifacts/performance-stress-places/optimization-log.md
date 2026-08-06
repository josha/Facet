# Performance-lab optimization log (roadmap Step 9, acceptance PL-17)

**Date:** 2026-08-04. Every entry follows the plan's loop: reproduce with one named
scenario → repeated baselines → **state a falsifiable cause before changing code** →
smallest change → focused + full + perf gates → rebuild → repeated after-captures →
cross-scenario regression check. Negative and inconclusive attempts are here too;
they are the entries that stop the next stage repeating them.

Two labels are never mixed below. **Lune** is the headless host with no engine and
no frame. **Studio** is the real adapter on the development host. Neither is a
device: the low-end Android rows are PL-P1/PL-P2 and remain `PENDING_PHYSICAL`.

---

## L-1 — the instrument was measuring an idle screen (LAB defect, not framework)

**Symptom.** The first Studio run of `dense-scroll` reported `focusTraverse`
visiting 0 of 24 rows, and 480 scroll steps left the core counters and the
GuiObject census byte-identical.

**Cause — stated, confirmed in behaviour, then CORRECTED in mechanism.** The driver
wrote `CanvasPosition` and measured in the same call, so the window never moved. It
looked fine headlessly because the fake target echoes synchronously — the classic
headless-blind class.

The mechanism first written here was "the property-changed signal lands on the next
frame". A fresh-context platform review showed that is wrong: under the default
`SignalBehavior.Deferred`, `GetPropertyChangedSignal` fires at the next *resumption
point*, normally later in the **same** frame. The genuine frame-boundary effect is
`CanvasPosition` clamping — the engine clamps against `CanvasSize - AbsoluteWindowSize`,
and that resolves on the engine's own schedule. The fix and the measurement are
unaffected (a frame wait is still required and still measured); the recorded rule is
corrected so the next stage does not reason from the wrong cause.

**Fix.** `scrollTo` waits one Heartbeat after the write (`telemetry.step()`);
`focusTraverse` and `keepVisible` read `pathOf` after the step rather than trusting
`focusKey`'s immediate return.

**After.** `focusTraverse` 8/8. Scroll genuinely moves the window.

**Second-order lesson, applied.** Timing the write *and* the frame wait together
produced a 26.6ms "worst scroll step" that was ~17ms of Heartbeat. The pass now
times the write and the re-window separately and stamps `frameWaitExcluded = true`;
a number that contains a frame wait is not framework cost.

---

## L-2 — a control-scope leak in the lab's own row (LAB defect)

**Symptom.** Suspicion, from a 9.9ms first-run `updateOne`, that stale readers were
accumulating.

**Falsifiable cause.** `newStepper` takes no `scope` key — it builds its own scope
and returns a `dispose`, unlike `newAsyncImage`, which accepts the cell scope. The
row assumed the second shape. If that is the cause, memo and scope counts must grow
with rows *visited*, not with rows *held*.

**Measurement (Lune, 2 000 rows, 400 steady scroll steps).**

| | after mount | after 200 | after 400 |
|---|---|---|---|
| memos | 96 | 8 278 | 17 078 |
| scopes | 31 | 2 078 | 4 278 |

Confirmed: linear in rows visited.

**Fix.** `scope:own(LuauUI.newStepper(...))` — the cell scope releases it.

**After (same probe).** memos 96 → 114 → 114; scopes 31 → 37 → 37. Flat.

**Durable regression.** `tests/perf_lab.spec.luau` — *"scrolling a virtualized list
does NOT grow the reactive core"* — bounds memo and scope growth over 240 scroll
steps. Mutation-tested: removing the `scope:own` reddens it, restoring it greens it.

**Not a framework defect, but a framework asymmetry worth knowing:** two shipped
composite controls have two different ownership shapes. Recorded as PLN-4; the API
question belongs to Step 7, not here.

---

## L-3 — the workload was a seek, not a steady scroll (WORKLOAD defect; versioned)

**Symptom.** The first MicroProfiler capture of "steady scrolling" read
`LuauUI/mount` at 12.5ms mean while measure + arrange + commit together were under
2ms.

**Cause.** `scrollProgrammatic` divided the whole canvas extent by the step count.
With 2 000 rows and 12 steps that is a 166-row jump per step, which replaces the
entire mounted window every time. That is a scrollbar drag, not a flick.

**Resolution — versioned, not fudged.** The scenario version went `perf-scenarios/1`
→ `/2`. `scrollSteady` advances a fixed 40px per frame (~0.67 rows at this pitch);
`scrollSeek` keeps the old behaviour under its honest name. Both are captured; both
are real interactions. **No older capture is compared against a `/2` number.**

---

## L-4 — arrange re-measures every scroll subtree (FRAMEWORK fix, shipped)

**Reproduce.** `lab-dense-scroll` (Lune) and `dense-scroll` / `scrollSteady`
(Studio), 2 000 rows, seed 1, 40px/frame.

**Repeated baselines (Lune, 200 steady steps, phase totals through the same
`profile.setHooks` recorder the engine uses):**

| run | `LuauUI/arrange` mean | `LuauUI/measure` mean |
|---|---|---|
| 1 | 1.6253 ms | 0.2421 ms |
| 2 | 1.6264 ms | 0.2442 ms |
| 3 | 1.6366 ms | 0.2430 ms |

**Falsifiable cause, stated before the change.** `arrange` is 6.6× `measure`, in the
pass that is supposed to be the cheap one. `solver.arrange`'s `scroll` branch calls
`measureAll`, which re-measures every child of the scroll node from scratch to
decide whether the engine scrollbar must be reserved off the cross axis. The measure
pass already computed those sizes at the same limits and threw them away. **If that
is the cause, memoizing `measure` per solve on (node, maxW, maxH, hiddenDepth) must
cut `arrange` substantially and change no geometry.** If arrange stayed flat, the
cause was wrong.

**Smallest change.** `src/layout/solver.luau`: `measure` becomes a thin per-solve
memo in front of `measureUncached`. The ctx is created fresh per `solve`, node
content does not change mid-solve, and every side effect `measure` has is an
idempotent write into a ctx table keyed by `node.id`; `hiddenDepth` is the one
contextual input not in the argument list, so it is part of the key. **The double
measure itself is untouched** — the scrollbar reservation still measures twice,
because "measuring twice is the cost of not guessing" is still true. Only the
recomputation is removed.

**Repeated after-captures (identical settings, three runs), at the CORRECTED memo —
the numbers below are the shipped ones, after the architecture review's BLOCKER-1 fix
made the cache replay its verdicts (see L-5):**

| run | `LuauUI/arrange` mean | `LuauUI/measure` mean |
|---|---|---|
| 1 | 1.2566 ms | 0.3289 ms |
| 2 | 1.1959 ms | 0.3310 ms |
| 3 | 1.2142 ms | 0.3241 ms |

`arrange` **−25%** against the 1.625–1.637 ms baseline, with no overlap between the
before and after sets. `measure` **+35%** — the memo's key construction, table writes
and verdict replay, paid honestly and recorded rather than netted out. Combined
measure+arrange 1.869 ms → 1.548 ms (**−17%**).

*(The first, incorrect version of the memo read −33% / +18%. Those numbers were real
but they belonged to a cache that was silently dropping verdicts; they are struck
rather than quoted, because a saving bought with a defect is not a saving.)*

**AND THE COST WHERE IT DOES NOT HELP**, which the reviews rightly asked for. On a flat
60-node tree — every node measured once, so the memo can only cost — three runs each
way: **0.276 ms/solve without, 0.297 ms/solve with (+8%)**. The trade is deliberate:
lists and scroll regions, the shapes this framework is used for, gain 25% on the pass
that dominates them; a flat screen pays 8% of a 0.3 ms solve. Both numbers are
published so a reader can disagree with the trade rather than guess at it.

**Gates.** Full LuauUI suite 3 361 passed (geometry invariants unchanged — the
suite contains the layout, hot-swap, large-text-matrix and composition families).
`tools/perf.sh` PASS. Rascal Rally consumer suite 3 089 passed at the judged source.

**Cross-scenario regression check** (reference profile p95, all 20 scenes). **Read the
caveat first:** this table was taken against the FIRST version of the memo — the one
BLOCKER-1 later condemned — so its magnitudes belong to that build. It is kept because
what it establishes is *direction across scenes* (nothing regressed), and because N-1
below is only interpretable beside it. The shipped memo's own numbers are the
repeat-measured ones underneath.

| scene | before | after | Δ |
|---|---|---|---|
| collection-mutation | 1.2043 | 0.6924 | −42.5% |
| theme-swap-flat | 0.1190 | 0.0595 | −50.1% |
| locale-textsize-change | 0.1164 | 0.0753 | −35.3% |
| lab-collection-churn | 3.4695 | 2.5287 | −27.1% |
| lab-dense-scroll | 4.7803 | 3.7817 | −20.9% |
| settings-churn | 0.5928 | 0.4788 | −19.2% |
| virtual-list-scroll | 2.0105 | 1.6755 | −16.7% |
| async-image-burst | 0.0230 | 0.0263 | +14.5% |
| stylesheet-state-churn | 0.0997 | 0.1134 | +13.7% |
| **native-scroll-drag** | **0.0195** | **0.0594** | **+204%** |

**The apparent regression was refuted — see N-1.** No scene regressed.

**THE SHIPPED MEMO, repeat-measured (7 runs of the reference profile each way, p95
median with min/max).** A single before/after pair is not a measurement — N-1 is the
whole reason — so the two lab scenes were re-measured properly after the BLOCKER-1 fix:

| scene | without the memo | with the shipped memo | change |
|---|---|---|---|
| `lab-dense-scroll` | 4.790 (4.524–5.290) | **4.207** (4.006–4.461) | **−12%**, ranges do not overlap |
| `lab-collection-churn` | 3.242 (3.132–3.430) | **2.695** (2.584–2.762) | **−17%**, ranges do not overlap |

Smaller than the −25% the `arrange` phase alone shows, which is expected: a scene's
total also contains mount, commit and react, and the memo touches none of them.

**Studio after-capture (real adapter, same settings, three repeats).** Worst
re-window 11.9 / 13.7 / 12.0 ms before → 11.0 / 11.1 / 10.5 ms after. Direction
agrees with the headless result; the Studio spread is wider, which is why the
distribution (p50/p95) replaced the single worst as the reported quantity.

**Budgets.** `lab-dense-scroll` and `lab-collection-churn` were re-baselined *down*
(17.742 → 15.144 ms and 12.387 → 10.412 ms) through
`tools/lune/perf_baseline_scene`, which touches only the named scenes. Re-baselining
after an improvement **tightens** the gate.

*Correction (phase-gate review F-3):* "every other scene's budget is byte-identical" was
too strong. Re-serialising the budgets file moved nine float fields across five untouched
scenes — at ~1e-16 relative, in both directions, i.e. JSON round-trip noise on the last
mantissa bit. **No budget was loosened**, and no threshold changed at any precision a
gate reads. The claim should have been "no other scene's budget changed in value", which
is what was checked.

---

## N-1 — NEGATIVE: the `native-scroll-drag` regression was noise

A single before/after pair showed +204% (0.0195 → 0.0594 ms). Seven repeats each way
on the reference profile:

| | min | median | max |
|---|---|---|---|
| before (memo bypassed) | 0.0337 | 0.0352 | 0.0398 |
| after (memo active) | 0.0260 | 0.0336 | 0.0404 |
| after (repeat) | 0.0253 | 0.0337 | 0.0355 |

The scene is **the same or slightly faster** with the memo. At 0.02–0.06 ms it sits
on the noise floor the budgets file already documents (a cheap scene's single-run
p95 is not a stable quantity). Recorded so the next reader does not chase it.

---

## N-2 — INCONCLUSIVE: the cold `updateOne` cost

The first `updateOne` pass of a session reports a worst single-row update of
6–10 ms; every later pass reports 0.45 ms. Twenty-fold, and stable at the low value
thereafter. The most likely explanation is first-touch text measurement of newly
seen formatted values (the Stepper readout has 21 distinct strings, so the cache
warms almost immediately), but **this was not isolated to a measurement**, and no
change was made on the strength of it. It is a candidate for the next stage: split
`updateOne` into a cold and a warm pass so the two are never blended, as the image
workload already does.

---

## What was deliberately NOT changed

- **Instance recycling in the keyed collection.** The native reference recycles a
  fixed pool of row frames; LuauUI's keyed `ForEach` creates and destroys subtrees,
  which is most of the 4.7× gap and all of the seek-workload `LuauUI/mount` cost.
  Changing it would rewrite mount-identity semantics that several shipped gates pin
  (repaint-vs-remount, focus survival, scope lifetime). That is an architecture
  decision, not "the smallest framework change" — decision packet **PLN-5**.
- **`UI.Text` measuring embedded newlines as one line** (found live; the lab's own
  counter block reserved a 29px box for six lines and reported `truncated = false`).
  Real defect, recorded as **PLN-6** and
  `docs/lessons/embedded-newlines-measure-as-one-line.md`. The measure path is
  Step 8.5 territory with a wide blast radius; the lab was changed to one text node
  per line instead.

---

## L-5 — the memo was WRONG, and a fresh-context review caught it (FRAMEWORK, fixed)

**Not found by me.** The architecture reviewer built a differential fuzz — two copies
of `src/`, one with the memo bypassed — and solved 800 seeded random trees at five
viewports with and without a scrollbar reserve, diffing the full per-node output.

```
cases=800  rectDiff=0  textFactsDiff=12  compactDiff=3  diagSetDiff=0  diagDupCountOnly=298
```

**Geometry byte-identical. Verdicts diverged.** That is the worst possible shape: the
box is right and the flag describing it is wrong, so nothing looks broken.

**Cause.** `ctx.compact` and `ctx.textFacts` are documented as "assigned on EVERY
measure of the node, so the facts published are the ones the reserved box was built
from" — **last write wins** across boxes, because a node is measured repeatedly at
different widths and `arrange` snapshots whatever the final measure left. A cache that
returned only `(w, h)` turned that into **first-measure-per-box wins**, which differs
exactly when the order is measure(A) → measure(B) → measure(A). *Call order is not
encodable in a cache key* — which is why no better key would have fixed it.

**Why it mattered more than it looked.** `compact` decides which string is painted.
`truncated` gates the full-value disclosure path and the reveal — and it flipped
**true → false**, so a cut label would have silently lost its accessible full value.
That is a Step 8.5 contract regression introduced by a performance change, with the
geometry unchanged.

**Fix.** The cache entry carries the verdicts and replays them on a hit. The double
measure the scrollbar reservation needs is untouched; only the recomputation is
removed.

**Verification, using the reviewer's own instrument:**

```
cases=800  rectDiff=0  textFactsDiff=0  compactDiff=0  diagSetDiff=0  diagDupCountOnly=298
```

**Durable regression.** `tests/measure_memo.spec.luau`, built from the review's
auto-shrunk minimal trees (seeds 132, 612, 91). **Mutation-proved**: deleting the
replay reddens the 612 and 91 cases — including the `truncated` one. The first version
of that spec was written from the review's *prose* and transcribed the dims as `w`/`h`
instead of `width`/`height`; it passed against the broken solver, which is exactly the
can't-ever-fail shape this repository removes on sight. It was only kept once the
mutation was seen to redden it.

**What this says about the loop.** The measured cause (L-4) was right, the fix
direction was right, the suite stayed green at 3 361 cases, and the change was still
wrong in a way only a differential oracle could see. The lesson is not "add more
tests" — it is that a cache in front of a function with *published side effects* needs
a differential check, not a spot assertion.

---

## L-6 — the optimization had to be SCOPED, because a gate said so (FRAMEWORK, shipped)

**How it surfaced.** The prior-gates sweep's `performance-unregressed` check was red, and
unlike every other red in that sweep it **also failed standalone**. That is the
discriminator between load noise and a regression, and it said regression.

**The scene.** `textinput-typing-storm` — a small tree re-solved per keystroke — crossed
`tools/bench.sh`'s 1.5× rule against its frozen baseline.

**Falsifiable cause, stated before changing anything.** The architecture review had
already predicted this as MINOR-8: *"on trees where nodes are measured once, the memo
costs ~20% of solve time, and nothing scopes it to the shapes that benefit."* A typing
storm has no scroll node, therefore no double measure, therefore nothing to save — only
a string key and a table per node per solve. **If that is the cause, an interleaved A/B
must show the memo consistently worse on this scene, and scoping it must remove the
difference.**

**Interleaved A/B** — sequential batches drift with machine state, so the two builds were
alternated within each pair:

| pair | unconditional memo | memo bypassed |
|---|---|---|
| 1 | 1.453 | 0.817 |
| 2 | 1.585 | 1.380 |
| 3 | 1.530 | 1.522 |
| 4 | 1.694 | 0.668 |
| 5 | 1.630 | 1.418 |
| 6 | 1.663 | 1.657 |

Worse in **6 of 6 pairs**. Cause confirmed; this was my change.

**What was NOT done.** Re-baselining `textinput-typing-storm` to accept the new number.
The plan's rule is explicit — a budget is never loosened to make a change pass — and the
scene's baseline is another stage's evidence.

**The fix: scope the memo to the shapes it exists for.** `ctx.hasScroll` flips the first
time a `scroll` node is measured, and the cache is consulted and populated only while it
is set. A scroll node is always measured before its own children, so the flag is armed
before any call that could benefit; a tree with no scroll region never touches the cache
at all.

**After, same interleaved method:**

| pair | scoped memo | memo bypassed |
|---|---|---|
| 1 | 1.159 | 1.623 |
| 2 | 1.621 | 1.191 |
| 3 | 1.610 | 1.343 |
| 4 | 1.448 | 1.456 |

Mixed in both directions — the two builds are now indistinguishable on this scene, which
is the correct outcome for a change that should not touch it. (The scene remains flaky
around the 1.5 threshold in **both** builds; that is pre-existing and is why it sits in
the bench allowlist.)

**And the win survives, measured the same way** — `lab-dense-scroll`, seven repeats per
build, alternated:

| pair | scoped memo | memo bypassed |
|---|---|---|
| 1 | 4.523 | 5.154 |
| 2 | 4.579 | 5.149 |
| 3 | 4.496 | 5.003 |

**−11%**, no overlap. `LuauUI/arrange` stays at 1.199 ms against the 1.625–1.637 ms
baseline — the scoping costs the beneficiary nothing, because the beneficiary is exactly
what it is scoped to.

**The lesson.** A reviewer predicted this in a MINOR and I shipped the change anyway
because the workload I cared about got faster. The gate caught it. An optimization
measured only on the shape it was written for is half a measurement — and "it did not
regress the scenes I looked at" is not the same claim as "it did not regress."

---

## L-7 — the baseline moved because the WORKLOAD moved (perf-row/2 → perf-row/3)

**Not an optimization. A re-baseline, recorded here so nobody reads the new numbers as a
win.**

Three layout defects found on a real phone and on the ten-foot matrix row changed the
workload's geometry:

- the row restacks into a three-band form below a measured 720px (`perf-row/2`), so a
  compact row is 152px rather than 56px and fewer rows are windowed;
- the row height now follows `typographyScale`, which a `Large` display class multiplies
  by 1.5 (`perf-row/3`);
- the list height subtracts every inset the renderer subtracts, including the ten-foot
  overscan margins.

Per the stage rule — *never weaken a workload to pass; version changed workloads* — the
row module went to `perf-row/3` and the scenario module to `perf-scenarios/3`, and the
entire previous capture set was marked **superseded** rather than edited or deleted.

### The replacement baseline

Studio host, 907×1044, 2 000 rows, flat theme, clean capture, 30 warmup / 120 capture
frames, `scrollSteady=200`, three repeats each (`pl9-row3-*.json`):

| build | RenderCPU p50 | p95 | mounted rows | LuauUI GuiObjects |
|---|---|---|---|---|
| LuauUI | 3.01 / 2.91 / 3.02 ms | 3.50 / 3.45 / 3.55 | 20 | 470 |
| raw-Roblox reference | 3.21 / 3.13 / 3.19 ms | 3.92 / 3.98 / 3.90 | 22 | 0 |

**Read this carefully, because it is easy to over-claim.** `RenderCPUFrameTime` is the
whole Studio frame, not LuauUI's share of it, and at this workload the two builds are
within noise of each other on that metric. It does **not** say LuauUI now matches raw
Roblox; it says this metric cannot separate them here. The per-operation comparison
(≈3.9× on the framework's own scroll-step work) was measured with a different instrument
at `perf-row/1` and is **not** carried forward — it needs re-taking at `perf-row/3`
before it can be quoted again. Recorded as an open item rather than restated.

The native reference's GuiObject count reads 0 because the census counts LuauUI's own
tree; the raw ScreenGui is outside it. That was true of the previous set too, where the
23.6-vs-9.2 per-row figure came from a separate instance walk. Also owed a re-take.

### N-3 (negative result) — the first attempt at a measured list height

Before the inset-fact fix, the list height was measured back from the surface's own
solved rect via `onGeometry`. It failed on contact: the screen hugs its content, so
`screenRect.h` is a function of the list height it was supposed to produce — a feedback
loop that settled at 143px on a 390px screen and tripped the audit on a state that was
about to correct itself. It also had no answer for the raw-Roblox path, which has no
LuauUI surface to measure. Abandoned in favour of reading the renderer's *inputs*
(`coreSafeInsets` + `effectiveOverscanInsets` under `distanceProfile`), which has neither
problem. Kept here because "measure it instead of computing it" is usually the right
instinct and was the wrong one here.

---

## L-8 — Run all, and the three bugs pressing it found (perf-row/3 → perf-row/4)

The director asked for one button that fires every scenario in sequence, ending in a
state where a single MicroProfiler dump covers the whole sweep. Building it was
uneventful. **Pressing it was not** — the sweep is the first thing that ever ran the
nine workloads back to back on a phone viewport, and it found three defects in one press
that nine months of running them individually never could.

**1. A stale safe-area reservation (the worst of the three).** The overlay publishes its
measured height into `coreSafeInsets.bottom`; the workload re-solves against that fact
the instant the viewport changes, *before* the overlay has re-solved. `layout-style-churn`
drives 907×1044 → 390×844 → 844×390, so the workload got the tall screen's 268px
reservation against a 390px screen: a **64px content box**, overflowing by 75px. The
remount the arrangement observer had just started failed inside a reactive flush, the lab
sat unmounted, and the *next* pass reported `no implementation is mounted` — a message
three steps downstream of the fault. Fixed by dropping the reservation to zero on any
viewport or type-scale change: for the one solve before the overlay republishes, the
workload believes it has more room than it has, which cannot overflow. Mutation-proved.

**2. Order-dependent workload settings.** `select` only applied a scenario's `content`
when the scenario declared one. `large-text-overflow` declares `content = "identity"`, so
**every workload after it in the sweep silently inherited long identity strings** — three
of them failed a layout audit for a reason that had nothing to do with them, and every
one of them passed when run alone. Selecting a scenario now states the whole
workload-owned setting set. Mutation-proved.

**3. A row free to wrap inside a fixed slot.** With identity content on a 360px screen, a
long name wrapped to a second line and painted 5px into the next row. The row's two texts
were the only things in a fixed-height `VirtualList` slot able to grow. Fixed with
`lineLimit = 1` on both, `disclose` already keeping the full name reachable.
**Not mutation-proved headlessly, and the test says so**: removing `lineLimit` leaves the
suite green because headless text measurement does not wrap the way the engine does. It
is proven in Studio, where the same portrait sweep goes 1 failure → 0.

Versioned to `perf-row/4`; the `perf-row/3` capture set is marked superseded.

### Replacement baseline — and why it does not settle anything

Studio host, 907×1044, 2 000 rows, flat, clean capture, `scrollSteady=200`, 3 repeats:

| build | RenderCPU p50 (r1 / r2 / r3) |
|---|---|
| LuauUI | **16.19** / 3.39 / 3.86 ms |
| raw-Roblox reference | 5.05 / 5.28 / 5.53 ms |

**The 16.19 is not a measurement and is published anyway.** It is the frame *interval*
at 60fps, and the capture's own `seriesAgreement.suspiciouslyPinned` flag says so. It
appeared on the FIRST repeat in both takes of this set — reproducible, so it is a
property of the first capture after a settle, not a random spike. Deleting it would have
made the table tidier and the record false.

Across the two takes, the native reference moved 2.87–2.93 ms → 5.05–5.53 ms with no
code change. **These Studio numbers are not stable enough to separate the two builds at
this workload**, and no claim is made that they do. The instrument that could — the
per-operation scroll-step comparison that produced the ≈3.9× figure at `perf-row/1` —
is still owed a re-take, and is still not quoted until it has one. Device measurement
remains authoritative (§14.3); PL-P1/PL-P2 stay PENDING_PHYSICAL.

---

## L-9 — the measure cache was keyed on a field the computation never reads

**The change:** one line in `solver.measure`. For a **text leaf whose height cannot
depend on the offered height**, `maxH` leaves the cache key.

**How it was found — the MicroProfiler, not a guess.** A LibMP capture of the lab
scrolling 2 000 rows at 360×691 gave the per-phase split for the first time:

| phase | ms/frame | calls | ms/call |
|---|---|---|---|
| `LuauUI/scenario` (all LuauUI work) | 2.786 | 166 | 2.786 |
| `LuauUI/arrange` | 1.302 | 81 | 2.668 |
| `LuauUI/commit` | 1.081 | 125 | 1.435 |
| `LuauUI/mount` | 0.567 | 44 | 2.141 |
| `LuauUI/measure` | 0.234 | 81 | 0.479 |

`measure` looks cheap and is not: a headless probe showed **98% of all measure calls
happen inside the arrange pass**, so they are billed to `arrange`. Attributing solve
cost by node kind (skip one kind's work, re-time) put **text at 31% of a solve**, and a
per-node count found **5.67 measure calls per text node per solve** — against a cache
that was serving **4.4%** of them.

**The cause.** The key was `{maxW}|{maxH}|{hiddenDepth}`. A container measures a child
against the height *remaining* after its siblings, so `maxH` differs on nearly every
call — while a text node's answer does not depend on it at all. `contentSize`'s text
branch computes from the wrap width and never reads `innerMaxH`. The one field that
made every key unique was the one field the computation ignored.

**The rule shipped.** `maxH` is dropped only when `resolveAxis` provably answers without
reading its `limit`: height type `fixed`, `content` or `minMax`. `fill`, `percent` and
`hug` all read it (`hug` caps at the offer), and either axis being `aspect` couples the
two. Containers are excluded entirely.

**Result.** Cache hit rate **4.4% → 39.2%**.

Headless, interleaved, `lab-dense-scroll` @ floorAndroid 360×640 — **22% faster, 5/5
pairs, no overlap**:

| pair | optimized | baseline |
|---|---|---|
| 1 | 0.681 | 0.931 |
| 2 | 0.724 | 0.884 |
| 3 | 0.688 | 0.891 |
| 4 | 0.695 | 0.877 |
| 5 | 0.728 | 0.890 |

Cross-scene (the check L-6 taught): `lab-collection-churn` −27%, `virtual-list-scroll`
−11%, `dense-hud` / `settings-churn` / `screen-lifecycle-churn` / `theme-swap-assets`
neutral, `hud-binding-storm` +5% at 0.09 ms (noise; a scroll-less tree never reaches the
cache at all — the `hasScroll` gate returns first). Full bench PASS, no budget touched.

Studio, phone portrait 360×691: `arrange` **2.668 → 2.026 ms/call**, `scenario`
**2.786 → 1.933–2.278 ms/frame** (run-to-run spread is real, see below).

### Verified by differential fuzz, and here is exactly what that did and did not prove

400 seeded trees, each wrapped in a scroll root so the cache is armed, solved by two
builds — one with the drop, one without — comparing `x/y/w/h` **and** `compact`,
`truncated` and `textState` per node. **Identical on all 400.** The cache was heavily
exercised: 3 306 calls, 1 114 hits, and the generator did produce the risky shapes
(text nodes with `percent` and `hug` heights).

**What it did NOT prove:** that the exclusions are load-bearing. Making the rule
deliberately over-broad (drop `maxH` for *every* text node, `fill`/`percent`/`hug`
included) produced **identical output too** — the fuzz never constructed the exact
interleaving that would expose it, and two hand-built attempts at a biting case failed
to place the nodes in `result.rects` at all. So the exclusions rest on reading
`resolveAxis` line by line, not on a test that has been watched to fail. Recorded as a
known gap rather than dressed up: this is the second cache in this function, and the
first one was wrong in a way only a differential oracle could see.

### N-4 (negative result) — caching the laid-out string

The obvious move — memoize `text_metrics.measureAt` on
`(font, size, width, lineHeight, maxLines, text)` — was built, generation-guarded
against `setMeasured`/`calibrate`, and **reverted**. Interleaved A/B: **neutral to worse
in 5/5 pairs** (0.94/0.94/0.94/0.94/0.95 cached vs 0.91/0.91/0.94/0.94/0.94 baseline).

The reason is structural and worth keeping: **a scroll brings new strings**. The word
store already removes the per-glyph cost; a string-keyed cache on top of it can only hit
when the same string is re-measured, and in a virtualized list the strings turn over as
fast as the rows do. It would pay on a static screen re-solving (theme swap, resize) —
which is not the hot path. Cache the *shape* of the repeat (same node, same width,
different offered height), not the *content*.

### The device-emulator matrix, optimized build

All five columns are `ms/frame` over a 200-step `scrollSteady` of 2 000 rows, clean
capture, LibMP frame limit 256.

| emulator row | viewport | `scenario` | arrange | commit | mount | measure |
|---|---|---|---|---|---|---|
| compact-phone-portrait | 360×691 | **1.93** | 0.47 | 0.14 | 0.66 | 0.12 |
| compact-phone-landscape | 706×339 | **1.60** | 0.33 | 0.11 | 0.66 | 0.09 |
| tablet-landscape | 1080×810 | **3.52** | 1.18 | 0.29 | 0.92 | 0.40 |
| desktop (no simulation) | 907×1044 | **4.04** | 1.42 | 0.33 | 0.97 | 0.49 |

Cost tracks **mounted row count**, not device class — which is the expected shape for a
windowed list and a useful negative result in itself: emulating a phone does not make
the work smaller in any way that reflects phone *hardware*, it only shrinks the window.

**Run-to-run spread is real**: the same phone-portrait configuration read 2.278 and
1.933 ms/frame in two captures of the same build. Treat differences under ~15% in this
instrument as unresolved.

### Against the target (artifacts/performance-stress-places/low-end-target.md)

Target **≤ 0.40 ms/frame**; phone portrait is at **1.93**. **~4.8× over.** Not close yet.

The largest remaining component at every viewport is now **`mount` (0.66–0.97 ms/f)** —
materializing rows as the window slides. The earlier capture's 29 156 `$newindex`
property writes (176/frame) are that churn, not steady-state rewrites: `renderer`
already guards rect writes behind `rectsEqual` and prop writes behind per-path last-value
checks. **Instance recycling (PLN-5) is therefore the top remaining lever**, and it is a
renderer-level change too large to land without its own verification pass.

Second candidate: extend "key on the inputs actually read" from text leaves to
**containers**, recursively (a container is height-free iff its own height dim is
extent-independent *and* every child is height-free). The remaining misses are 1 088
text and 1 088 hstack per 20 solves, so the headroom is real — but the blast radius is
the whole layout algorithm, and the fuzz above could not even construct a biting case
for the *text-only* over-broad rule. Not shipped on that evidence.

---

## L-10 — instance recycling: built, proven correct, and it buys almost nothing

**Shipped OFF (`opts.recycleInstances`, default false). This is a negative result.**

### The idea, and the measurement that motivated it

A windowed list destroys a row at one end and builds an identical one at the other every
time the window slides, for no reason except that the row's PATH changed. Measured on the
engine in a Studio Play session: building one 24-object row **0.252 ms**, destroying it
**0.045 ms**, rewriting the same 24 objects' properties **0.024 ms** — **12× cheaper**.
`LuauUI/mount` (the structural pass) was **0.66–0.97 ms/frame** at every viewport, the
largest single component of a frame. The case looked overwhelming.

### What was built

- `adapter.park` / `adapter.adopt` / `adapter.discardParked` — a three-call optional
  contract, feature-detected. `park` refuses any node carrying path-keyed adapter state
  (decoration, chrome text, toggle parts, stroke, motion scale, canvas group, clip-host
  ROLE, presentation transform) and a refusal falls straight through to the ordinary
  remove, so the feature can only ever do nothing — never something different.
- A bounded pool in the renderer (cap 64), keyed on the creation-time facts the adapter
  baked in: class, decoration hint, canvasGroup.
- Mirrored in the fake target so the behaviour is testable headlessly.

**It works.** Over a 200-step scroll of 2 000 rows at 360×691: creates **1 178 → 458**,
720 instances served from the pool, 80 parks correctly refused (the Toggle and the
stepper Buttons, which carry chrome children).

### It made no measurable difference

Interleaved, same session, two pairs:

| pair | `mount` on | `mount` off | `scenario` on | `scenario` off |
|---|---|---|---|---|
| 1 | 0.639 | 0.638 | 1.900 | 1.892 |
| 2 | 0.653 | 0.680 | 1.936 | 1.967 |

### Why — the arithmetic error, stated plainly

The 12× figure was measured correctly and **applied wrongly**. It is the cost of churning
a *whole row*, and I assumed a whole row churns every frame. It does not:

```
engine cost per GuiObject (create+destroy)   12.4 us   (0.297 ms / 24)
instances actually recycled per frame         2.8      (720 over 256 frames)
=> theoretical saving                         0.035 ms/frame
   measured LuauUI/mount                      0.64  ms/frame
   so Instance churn is AT MOST 5% of it
```

A 61% cut in Instance creations bought ~0.035 ms/frame, which is inside this
instrument's noise (~15%). The measurement was never going to show it.

### Where `mount`'s 0.64 ms actually goes — and the evidence

`structuralSync` is **O(all live nodes)**, not O(churned nodes): it walks the tree into
`livePaths`, sweeps *every* entry in `handles`, and re-runs `syncZOrder`. The device
matrix already contained the proof, in data taken before any of this was built:

| row | mounted rows | `mount` ms/f |
|---|---|---|
| compact-phone-landscape | 6 | 0.66 |
| compact-phone-portrait | 7 | 0.66 |
| tablet-landscape | 11 | 0.92 |
| desktop | 13 | 0.97 |

**Mount scales with how many rows are LIVE, while the churn rate per scroll step is the
same at every viewport.** That is the signature of a full sweep, and it is inconsistent
with Instance churn being the cost. The number was on the page before I started.

### Disposition

The code is **kept and shipped OFF**. It is correct (see below), costs one boolean test
per create and per remove when disabled, and is the right mechanism for a consumer whose
rows are much larger or whose list scrolls much faster — the saving scales with churn,
and this workload simply does not churn enough. Enabling it by default would be adding a
moving part for no measured gain.

**Correctness evidence** (`tests/instance_recycling.spec.luau`): the invariant is that a
recycled node is indistinguishable from a fresh one, so every test is a DIFFERENTIAL —
the same scenario run with recycling on and off, comparing every live node's path, class,
rect and every property, at every step of a 30-step scroll and again after scrolling back
to the top.

**Mutation-proved, and it took two attempts to make the oracle bite.** With uniform rows,
deliberately skipping the property reset in `park` left the entire suite **green**: while
every row declares an identical prop set, a stale value is always overwritten and no
differential can see it. A `ragged` world was added where every third row declares a
`textAlign` the others do not — the pool then hands a node that carried the prop to a row
that does not declare it, and the mutation now fails that case loudly. The first version
of this spec was a test that could not fail.

One more self-inflicted trap worth recording: the first snapshot function used
`tostring(v)` for every property, so table-valued props (`textFont` is a descriptor
table) stringified to their **heap address** — which differs between two separately built
worlds by construction. Every differential "failed" on rows whose geometry and text were
byte-identical. **A comparison that includes an address is a comparison that can never
pass, and it looks exactly like a real defect.**

---

## L-11 — recycling turned ON by default, and the layout-granularity gap it exposed

### Recycling: default ON

L-10 shipped it off because a *steady* scroll saved 0.035 ms/frame — noise. The
director's question ("shouldn't this help scrolling large lists?") was the right one, and
the answer is that **the saving is proportional to churn, and a creep is not what churns
a list — a fling is.** Measured on the same workload:

| motion | objects saved | per event | saved on the M4 |
|---|---|---|---|
| steady scroll (creep) | 720 over 256 frames | 2.8/frame | **0.035 ms/frame** |
| seek / fling (jump) | 3 776 over 60 steps | **62.9/jump** | **0.78 ms/jump** |

0.78 ms of avoided *engine* work per fling step, on a machine where the whole LuauUI
frame is 1.9 ms. On a low-end Android that same work is several times more expensive
again, and it lands on exactly the frames a list feels worst on.

Default flipped to **on**; `recycleInstances = false` opts out. It is safe by
construction — `park` refuses any node it cannot take intact and the refusal falls
through to the ordinary remove — and correctness is pinned by the mutation-proved
differential in `tests/instance_recycling.spec.luau`. Verified: LuauUI suite 3 404,
RascalRally suite 3 089, perf bench PASS, gate PASS 22/22.

### The gap the question exposed: there is no incremental layout

Asked whether a change to one bound value re-lays-out only that node's chain, the answer
turned out to be **no, it re-lays-out everything**:

```
full re-layout (viewport change)  arranged 58 nodes, measured 191
ONE bound text changed            arranged 58 nodes, measured 191   (100%)
```

`solveAndApply` solves from the root on every dirty pass. A ticking counter in a corner
costs the same as a rotation. The reactive core IS fine-grained — the earlier
`fine_grained_reactivity.spec` proves a single-row write produces a constant number of
renderer writes independent of collection size, at 200 / 2 000 / 20 000 rows — but that
is the WRITE path. The SOLVE path has no such granularity.

**Instrumented rather than asserted from reading the code**: `solver.solve` now publishes
`work = { arranged, measured }`, the renderer surfaces it as `stats.lastArranged` /
`lastMeasured`, and `fine_grained_reactivity.spec` has a case that records the ratio.
That case deliberately does **not** assert the good behaviour — a red test nobody can make
green is noise. It asserts the ceiling (one change can never cost more than a full
re-layout) and is the place the win will show up when incremental layout lands.

### Revised lever list

| lever | evidence |
|---|---|
| **Incremental layout** | one bound change = 100% of a full re-layout. The biggest structural gap found in this whole pass |
| **Incremental `structuralSync`** | `mount` is O(all live nodes): 6 rows 0.66 ms/f → 13 rows 0.97 ms/f while churn per step is constant |
| ~~Instance recycling~~ | done, on by default, 0.78 ms per fling |
| ~~Measure-key fix (L-9)~~ | done, −22% headless, arrange 2.67 → 2.03 ms/call |

---

## L-12 — the `resize-relayout` workload, and the incremental-layout prize measured

New workload (`perf-scenarios/4`), director ask: resize continuously and interleave
single-value changes, so the two costs are reported **separately** instead of blended.

Studio, 360×691, 2 000 rows, 40 steps each:

| event | p50 | p95 | worst | nodes arranged |
|---|---|---|---|---|
| viewport resize | 3.46 ms | 6.14 ms | 11.0 ms | **121** |
| ONE bound value changed | 1.27 ms | 3.47 ms | 5.94 ms | **121** |

**`dataChangeShareOfFullRelayout` = 1.00.** Changing one string re-arranges the entire
tree. A resize legitimately does; a single value has no business doing it.

Note the two are not equal in TIME even though they arrange the same nodes — a resize
also re-measures text at new widths (cache misses by construction), while a value change
mostly re-measures at widths already in the per-solve cache. Arrange count is the
structural measure; ms is the total including measurement.

**Scaled to the target device**: 1.27 ms p50 on an M4 is ~28 ms at the estimated 22×
single-thread gap — a dropped frame at 30 fps, for one character changing. This is now
the single largest gap between LuauUI and the low-end goal.

Two instrument fixes this pass paid for:
- the first version picked its victim row from the whole 2 000-row dataset, but a row's
  value signal is created lazily when the row MATERIALIZES — so 2 of 40 steps found a
  signal and the data-change sample was two readings wide. It now picks from the live
  window.
- headlessly the harness runs a FAKE clock, so only the arranged COUNTS mean anything
  there; the ms figures above are from a real Studio session.

---

## L-13 — incremental layout, Stage 1: the prize is 5.2× and the distribution is flat

**Detection only. No layout behaviour changed, and an ordinary frame pays nothing** —
the analysis runs only when `controller.analyzeBoundaries()` is called.

`solver.solve(..., { analyzeBoundaries = true })` records per node whether its own size
can change because something inside it changed. The predicate mirrors `resolveAxis`
case for case, because a boundary rule that disagrees with the resolver is worse than
none — it would promise a subtree is isolated when it is not:

| dimension | absorbs a child's size change? |
|---|---|
| `fixed` | yes — a literal |
| `percent` / `fill` | yes **iff the axis is bounded** (both fall back to content on an unbounded axis, and `resolveAxis` files a diagnostic when they do) |
| `minMax` | iff `preferred` is set (otherwise it is `contentFn()`) |
| `hug` / `content` | no |
| `aspect` | defers to the other axis |

`solver.boundaryReport` walks each node to its nearest absorbing ancestor (inclusive) and
counts that subtree. Measured on dense-scroll at 360×691:

| | |
|---|---|
| nodes | **104** |
| absorbing nodes | **28** |
| re-arranged for one change **today** | **104** |
| ...with boundaries honoured | **20** (mean, median *and* p95) |
| share of tree | **19% — a 5.2× cut** |

**Mean = median = p95**, so the saving is uniform, not concentrated. Carried to L-12's
timings: one bound value 1.27 ms → ~0.24 ms here, and ~28 ms → ~5.4 ms at the estimated
22× device gap.

Pinned by a case in `tests/perf_lab.spec.luau` that asserts a ceiling
(`meanShareOfTree < 0.5`) rather than the measured value — an ordinary layout edit
should not redden it; what it protects is the claim the plan rests on, that boundaries
exist and isolate most of the tree.

**Recommendation recorded in `docs/plans/incremental-layout.md`: proceed to Stage 2**
(skip arrange when a dirty node re-measures to the same size, re-arranging only its
subtree). Stage 2 is where the risk starts — `ctx.compact` / `textFacts` / `textStates`
are last-write-wins across the whole solve, so a partial solve changes published verdicts
even when geometry does not, and that is exactly the class the measure-memo BLOCKER was.

---

## L-14 — the Studio visual-regression harness, and Stage 2 attempted and REVERTED

### The harness (kept — `tools/studio/visual_diff.luau`)

Built before the change, on purpose. It reads what the **engine** resolved for every
GuiObject on the surface — `AbsolutePosition`, `AbsoluteSize`, `Visible`, `ZIndex`,
`ClipsDescendants`, text, image — not what LuauUI asked for. The headless differential
compares the fake adapter's virtual state, which is necessary and not sufficient: it
cannot see engine rounding, native scroll offsets, clip-host re-parenting or ZIndex, and
those are exactly where a partial solve could go wrong.

**Not a screenshot diff, deliberately.** Pixels tell you *that* something moved; this
tells you *which node* and by how much — the difference between a finding and a hunt.
Screenshots stay for human review; the two answer different questions.

**It was proven stable before being trusted.** `visual_diff.selfCheck` runs the same
configuration twice and requires a zero diff. Result on the live workload: **155 nodes,
0 differences.** An instrument that is not stable under no change reports every real
comparison as a failure, and a green result from one that has never been checked means
nothing.

### Stage 2: attempted, does not work yet, reverted

Implemented the narrow slice: when the only dirt is `measure`/`arrange` on nodes inside
ONE absorbing box, re-solve that box at the size it already has and splice the result —
rects translated back to absolute, diagnostics for nodes inside the box replaced and
those outside carried through, everything conservative (any uncertainty falls through to
the full solve).

**The partial path never engaged.** `stats.partialSolves` stayed 0 across every probe.
Instrumented the bail reasons and got `no-base` — `lastResult` reading as nil inside
`partialSolve` — while a counter on the assignment proved it *was* being set on every
solve. The two do not agree, so something about the closure or call ordering is wrong in
a way I did not isolate.

**Reverted rather than shipped.** A differential that passes because the feature never
ran is the exact failure this log has recorded twice already (L-10's recycling
differential was green against a broken build; the first `measure_memo` spec could not
fail). Shipping it off-by-default would have left debug counters in the renderer and an
optimization that looks present and does nothing — worse than not having it.

**Kept from this pass:** Stage 1 (`solver.boundaryReport`,
`controller.analyzeBoundaries`, measured 5.2×) and the visual harness. Both are useful on
their own and neither changes layout behaviour.

**For whoever picks up Stage 2:** the plumbing to debug first is the lifetime of
`lastResult`/`pendingDirty` relative to `solveAndApply` — start by proving the partial
path executes *at all* (assert `partialSolves > 0`) before writing a single correctness
test against it.

---

## L-15 — incremental layout Stage 2: root-caused, working, measured, and OFF by default

### The root cause of "it never engages" (L-14's open question)

`result.rects[id]` is not a rect. It is the solver's per-node **record** —
`{ rect, kind, textState, compact, textFacts, overflow, ... }`. The first attempt read
`.w`/`.h` straight off the record, got nil, and bailed on **every** solve while looking
entirely reasonable. Geometry lives one level in, at `.rect`.

Found by tracing every exit rather than reasoning about closures — the earlier theory
(upvalue scoping across `solveAndApply`'s four call sites) was wrong, and the counter
that "proved" the assignment was firing had been telling the truth all along.

### It works, and the saving is real

With the fix, on the performance lab in a live Studio session:

| | full solve | incremental |
|---|---|---|
| `lastArranged` for one bound change | **141** | **20** |
| partial solves taken | 0 | 2 of 2 eligible |

Headless, on a 300-row list over 40 single-value changes: `lastArranged` **87 → 4**.

### Three oracles, and what each one proved

1. **Headless differential** (`tests/incremental_layout.spec.luau`): paint,
   `controller.textAt()` facts and `controller.diagnostics()` compared at every one of
   40 steps. Three mutations were run and watched to redden it — drop the rect
   translation, flip the `compact` verdict, drop `textFacts`. The third only bites
   *since* `textAt()` joined the oracle; before that the same mutation left the suite
   green. `textState` remains uncovered and is named as an open gap.
2. **Engine-level visual diff** (`tools/studio/visual_diff.luau`, new): every GuiObject's
   `AbsolutePosition`, `AbsoluteSize`, `Visible`, `ZIndex`, `ClipsDescendants`, text and
   image, read back from the engine in a live Play session. **185 nodes, 0 differences.**
   Proven stable first (same build twice → 0), which caught a flaw in the instrument
   itself: keying by instance NAME collapsed every `LuauUIHitExpander` onto one entry and
   reported a phantom difference. Keys are now full ancestry paths.
3. **Screenshots**, full vs incremental — indistinguishable.

### Why it is still OFF by default

**Flipping the default reddens ten existing cases.** `theme_value_displays`, the rung-3
gauge, and a motion case that chases a moving target. One cause was found and fixed — a
`percent` box re-solved as a ROOT resolved its fraction against *itself* and came back a
quarter of its width, so the box's own size is now pinned to what it already had — and
others remain.

Those ten failures are the specification for the next pass, and they are worth more than
a green suite would have been: they are exactly the cases a single hand-built fixture
could not reach. **The plan called for a differential fuzz over seeded trees for this
reason** (docs/plans/incremental-layout.md, verification step 1); one fixture passed and
the real suite immediately produced counterexamples.

**A default-on layout change that reddens ten tests is not shippable, however good the
numbers are.** Opt in with `incrementalLayout = true` to measure it; the next pass starts
by making those ten green.

---

## L-16 — incremental layout v2: skip subtrees INSIDE one solve. Shipped ON.

### Why v1 could not be fixed

v1 re-solved the boundary subtree as its own **root** and spliced the result. That is
wrong in kind, not in detail: a sub-solve gets a **fresh `ctx`** (no `hasScroll`, so the
measure memo is off; `hiddenDepth` 0; zeroed insets) and a **screen-root policy applied
to a node that is not a screen**. Ten existing cases found ten ways that mattered — the
first being a `percent` box that, as a root, resolved its fraction against *itself* and
came back a quarter of its width.

Patching the symptoms (pinning the box's own size) fixed one and broke another. The
context differences are the design, not a bug in it.

### v2

**One solve, from the root, unchanged — with a skip.** `arrange` returns early for a
subtree when both hold:

- **nothing inside it is dirty** — the renderer hands the solver the *ancestor closure*
  of the dirty set, so a node absent from that set provably contains no change; and
- **it is landing on exactly the rect it already had** — so every descendant's absolute
  geometry is the answer it already gave.

Nothing is re-rooted, re-based or re-parented, so there is no second context to disagree
with the first. That is the whole difference.

Skipped subtrees **replay** their published channels — `textState`, `compact`,
`textFacts` — and their **diagnostics**, for the same reason `solver.measure`'s memo
replays them: a cache that returns geometry and drops the verdicts changes `compact` and
`truncated` while every rect stays byte-identical, which is the BLOCKER a differential
fuzz caught on that memo. Dropping the diagnostics would have silenced
`controller.diagnostics()` for exactly the parts of the screen that did not change.

### Result

| | full solve | v2 incremental |
|---|---|---|
| arranged, one bound change (Studio, 360×691) | **141** | **8** (133 skipped) |
| arranged, headless 300-row list | 101 | **7** |

**~17× less arrange work for an identical screen.**

### Verified

- **Full suite green with the default ON: 3 411.** All ten of v1's failures are green
  under v2 — the design change is what fixed them, not a patch.
- **RascalRally 3 089**, perf bench PASS.
- **Engine-level visual diff, live Studio**: 185 nodes, **0 differences** in
  `AbsolutePosition` / `AbsoluteSize` / `Visible` / `ZIndex` / `ClipsDescendants` / text /
  image, with the harness's `selfCheck` proven stable first.
- **Headless differential** over 40 changes: paint, `controller.textAt()` facts and
  `controller.diagnostics()` all identical, with three mutations watched to redden it.

**The harness earned its keep twice.** Once by catching a flaw in itself (keying by
instance name collapsed every `LuauUIHitExpander` into one entry and reported a phantom
difference — keys are now full ancestry paths), and once by refusing a comparison: adding
`selectRow` to the drive made `selfCheck` report **unstable**, because selection persists
across runs. A "0 differences" from a drive that cannot reproduce itself proves nothing,
and the instrument said so instead of letting it pass.

`incrementalLayout = false` opts out. `textState` remains the one published channel with
no mutation proving the oracle sees it.

---

## L-17 — where the numbers land after all of it, and the Fire HD 8 fling estimate

Fresh MicroProfiler captures on the shipped build (L-9 measure key + recycling ON +
incremental layout ON), Studio, 360×691, 2 000 rows, the full row (avatar image, two
labels, toggle, stepper, button):

| | `scenario` | `mount` | `arrange` | `commit` | `measure` |
|---|---|---|---|---|---|
| steady scroll | **1.97** | 0.664 | 0.520 | 0.123 | 0.155 |
| fling | **2.26** | **1.52** | 0.311 | 0.251 | 0.115 |

Against the start of this work: steady scroll `scenario` **2.79 → 1.97 (−29%)**, one
bound value **121 → 8 arranged nodes (−93%)**, creates per fling **9 964 → 6 188 (−38%)**.

**Incremental layout does nothing for scrolling, and the capture says so** — 1.97 with it
on, 1.99 with it off. Scrolling is structural, so the partial path correctly falls back.
It pays on data changes. Reporting it any other way would be dressing up a real win as a
bigger one.

**The fling frame is `mount`, not layout**: 1.52 ms of 2.26 is row materialisation;
arrange is 0.31.

### The estimate: ~15–25 fps flinging this list on a Fire HD 8

Split by kind of work rather than one blanket multiplier —

| component | M4 | assumed gap | on device |
|---|---|---|---|
| `mount` (engine allocation + property writes) | 1.52 ms | ~10× | ~15 ms |
| `arrange`/`measure`/`commit` (interpreted Luau) | 0.68 ms | ~22× | ~15 ms |
| | | | **≈30 ms/frame** |

At 30 fps the whole budget is 33 ms. **LuauUI alone would take ~30 of it**, leaving
nothing for render, input or the game. Steady scroll lands near 26 ms — about 30 fps with
no headroom.

**The 10× for engine work is the weakest number in this** and is called out as such in
`fire-tablet-estimate.md`: it is a judgement that C++ allocation scales better than
interpreted Luau across this gap, not a measurement. At 22× the fling frame is ~48 ms and
the answer is ~20 fps. GPU is entirely unmeasured — a GE8300 drawing 185 GuiObjects with
avatar images may or may not be a second constraint, and nothing here says which.

### The lever is no longer layout

**23.6 GuiObjects per row against 9.2 for the matched raw-Roblox reference — 2.6×.**
`mount` is 67% of the fling frame and scales with objects per row. That is a design
change to the row, not a framework fix, and it is worth more than anything left in the
solver. Second: a property diff on adoption (recycling avoids `Instance.new`/`Destroy`,
but every property is still rewritten because the per-path caches drop on park).

---

## L-18 — the property diff on adoption, and what it is worth

**The idea.** Recycling avoids `Instance.new`/`Destroy`, but every property was still
rewritten on adoption because the renderer's per-path caches were dropped when the node
was parked. `mount` is 67% of a fling frame, so that rewrite is where the remaining cost
is.

**The insight that makes it safe.** Those caches record what the ENGINE OBJECT holds —
they are a property of the instance, not of the path. Carrying them across a recycle is
*accurate*, not stale. So park stashes them on the handle and adopt restores them under
the new path, and `applyProps` then writes only what actually differs.

**Two things had to change for that to be sound, and both were found by tests, not by
reasoning:**

1. **The pool key now includes the declared PROPERTY-NAME SET.** Writing only
   differences is safe only if every property on the instance is one the new node also
   declares — otherwise a property the old identity set and the new one does not would
   survive with nothing to clear it. Two nodes share a bucket only if class, decoration
   hint, canvasGroup *and* property names all match. In a virtualized list every row
   comes from one blueprint, so they match; anything else takes the ordinary create path.
2. **`lastCompact` is NOT carried, and `Visible` is left alone by park/adopt.**
   `lastCompact` looks like a value cache and is not — it gates `applyCompactLabel`,
   whose *write* depends on the new node's label, so a carried `true` skips re-applying a
   different row's glyph. Caught by "a REMOUNTED button gets its verdict re-applied",
   itself the pin for a defect found live on RascalRally's watch-cycle buttons. Similarly
   park no longer writes `Visible`: the renderer's visibility pass owns it, and a write
   there would make the cache disagree with the instance.

The fake target also had to stop clearing properties on park — it was modelling an
adapter that does not exist and would have hidden the diff entirely — and to start
refusing a node carrying a presentation transform, which the live adapter already
refused. A fake that accepts what the real adapter refuses proves the wrong thing.

### Measured

| | creates | propWrites |
|---|---|---|
| headless, 60-step scroll, no recycle | 390 | 650 |
| headless, 60-step scroll, recycle + diff | **24** | **283 (−56%)** |
| Studio, steady scroll ×200, no recycle | 1 178 | 2 145 |
| Studio, steady scroll ×200, recycle + diff | **458** | **1 761 (−18%)** |
| Studio, fling ×10, no recycle | 1 733 | 3 159 |
| Studio, fling ×10, recycle + diff | **1 158** | **2 821 (−11%)** |

**No frame-time improvement is demonstrated.** Studio `scenario` reads 1.94 vs 1.95 and
`mount` 0.626 vs 0.637 — inside this instrument's ~15% noise. The work removed is real
and counted; the timing win is not measurable on the workload the profiler can reliably
capture, exactly as with recycling itself, because a steady scroll churns ~2.8 objects
per frame. The saving is proportional to churn and the fling is where it lands.

The Studio ratio (−11% to −18%) is smaller than headless (−56%) for an honest reason:
the live adapter writes more properties per node than the fake, and the ones that differ
between rows — `text`, `image` — must be written whatever happens. The diff removes the
ones that do not change between rows: size, font, padding, z, hit rect, visibility.

---

## L-19 — the GuiObject census, and the first framework-wide win it found

**The question was "reduce the lab's per-row object count". The census answered a better
one: most of the excess is not the row.**

A 5-row window on the live surface:

| | count |
|---|---|
| **total instances** | **249** |
| GuiObjects | 137 |
| **non-GuiObject modifiers** | **112** — `UICorner` 37, `UIStroke` 30, `UIScale` 25, `UIPadding` 20 |

**45% of every instance on the surface is a modifier**, and the row's own composition is
only part of the story. Modifiers are created per node by the ADAPTER, so anything
removable there is removable for every LuauUI consumer, not just this fixture.

### The finding: all 25 `UIScale` objects were inert

Every one sat at `Scale = 1.0`. They exist for the pressed dip — one per interactive
control, created at construction, for a dip that had not happened and on most controls
never will. **10% of every instance on the surface doing nothing**, paid by anyone with
buttons on screen.

### The fix: create it on first press, from ONE place

`ensureScale(instance, handle)` is now the single creation site, and both the press dip
and the motion channel go through it. That mattered: the engine honours a single `UIScale`
per instance, and there is an existing contract that motion and the press dip **share**
one. Laziness with two creation sites would have produced two and honoured neither — so
the test that guarded the old shape was rewritten to pin the stronger fact, that
`Instance.new("UIScale")` appears exactly twice in the adapter (the shared accessor, and
the focus ring's own).

### Measured, live

| | before | after |
|---|---|---|
| total instances, 5-row window | **249** | **224** (−10%) |
| `UIScale` on the surface | 25 | **0** |
| GuiObjects | 137 | 137 (unchanged, as intended) |

Behaviour verified with a real mouse press through the Studio input path, not a
simulated call: pressing a button creates `LuauUIMotionScale`, dips it to **0.985**,
recovers to **1.0** on release, and leaves **exactly one** `UIScale` on the entire
surface. At ~12.4 µs of engine work per instance, 25 fewer objects per window is ~0.31 ms
off a full window build.

### What is left, and where it belongs

`UICorner` 37, `UIStroke` 30 and `UIPadding` 20 are all doing real work in this theme —
none were inert, so none can simply be dropped. Candidates worth measuring next, in
order:

1. **`UIPadding` with all-zero padding** — none found inert here, but a theme with no
   control padding would produce them, and eliding a zero-valued modifier is free.
2. **`UIStroke` when the theme's hairline is fully transparent** — same shape.
3. **The row's own composition** (23.6 GuiObjects vs 9.2 for the raw-Roblox reference)
   is the remaining consumer-side lever, and it is a design change to the row rather
   than a framework fix.

The framework-wide portion of this work is done: the inert-by-construction case is gone,
and the remaining modifiers are earning their place.

---

## L-20 — hairline elision, and the row-composition task answered by measurement

### Hairline elision (shipped, zero measured win, said so)

`hairline()` now refuses to build a `UIStroke` that would draw nothing — zero thickness
or full transparency. **Both shipped themes keep hairlines visible, so this saves nothing
today.** It is one comparison at construction, and it exists for a theme package that
turns hairlines off, which on the measured shape would otherwise pay ~30 invisible
strokes per five rows. Pinned by a source-shape test that also asserts the guard runs
BEFORE `Instance.new` — an elision checked afterwards saves nothing.

`UIPadding` was examined and left alone: none were zero-valued, and both creation sites
write real values from the theme.

### Row composition: there is nothing to cut on the row

The premise was that the lab's row uses 23.6 GuiObjects against 9.2 for the raw-Roblox
reference. Enumerating one row:

| | count |
|---|---|
| **CONTENT** (image, 2 labels, toggle, button, 2 stepper buttons, 2 stepper labels) | **9** |
| layout containers | **11** |
| raw-Roblox reference | 9.2 |

**The row's content is already at parity with native — 9 against 9.2. The entire 2.6×
gap is framework container instances.** Cutting the row would mean deleting controls the
workload exists to exercise. The objects are the framework's, and so is the fix.

### The 40% finding

Across the surface (137 GuiObjects): 37 paint, 1 clips, 30 are interactive, 38 carry
modifier children — and **55 (40%) are completely inert**: no paint, no clip, no
interaction, no modifiers, no text or image.

**In LuauUI's flat tree they are not even the engine parent of their children** —
`adapter.create` parents everything to the root and the solver positions absolutely. An
inert container is an invisible zero-child `Frame` holding a rect nothing reads. At
~12.4 µs per instance that is **~0.68 ms per full window build**, against a `mount` that
is 67% of a fling frame.

**Not started, deliberately.** `handle.instance` is dereferenced **47 times** in the
adapter; every one must tolerate absence or force materialisation, and one missed site
produces a missing node rather than a slow one. Patching 47 symptoms at the end of a long
pass is exactly how incremental-layout v1 failed. Scoped in
`docs/plans/inert-container-elision.md` with the design (lazy instance, same shape as the
`UIScale` fix that shipped this round), the verification plan, and the note that several
existing instance-census tests will need expectations re-derived from the new rule rather
than adjusted to whatever the code emits.

**Expected: ~11 of 20 objects per row, taking the row from 23.6 to roughly the native
9.2 — the whole gap that started this line of work, for every consumer.**

---

## L-21 — inert container elision: 40% of GuiObjects were doing nothing. Shipped ON.

**The design.** A pure layout container gets a HANDLE and no engine object, and
materialises the instant anything needs one. Same shape as the lazy `UIScale` shipped
alongside it: the cheap case is free, the real case is unchanged.

Eligibility is **creation-time and conservative** — `VStack`, `HStack`, `ZStack`, `Grid`,
`Anchor`, `Spacer`, and only when the node carries no decoration hint and no
`canvasGroup` declaration. `create` cannot know whether a node will later be given a
surface or a handler, so `ensureInstance` covers everything else by materialising on
demand.

**Why this is sound at all: LuauUI's tree is FLAT.** `create` parents every node to the
root (or the nearest clip host) and the solver positions each one absolutely. A container
is therefore *not* the engine parent of its children — so an unpainted, non-clipping,
non-interactive one is an invisible zero-child `Frame` holding a rect nothing reads.

**The entry points, and which do what:**

| | |
|---|---|
| `setRect`, `setVisible`, `setZOrder` | **no-op**, value recorded for later materialisation |
| `setProp`, `setHitRect` | **materialise** — these need a real object |
| `park` | refuses an elided handle (nothing to pool) |
| `remove` | drops the path records; there is nothing to unwind |

`ensureInstance` folds the built handle into the existing table rather than replacing it —
the renderer keys everything off that exact table — and re-registers `handlesByPath`,
`instancesByPath` and the clip-host child entry, which would otherwise point at a
throwaway table nobody else references.

### Measured, live

| | before | after |
|---|---|---|
| **GuiObjects** (5-row window) | 137 | **91 (−34%)** |
| `Frame` | 55 | **9** |
| total instances | 224 | **178 (−21%)** |
| fling `LuauUI/scenario` | 2.26 ms/f | **~1.90–2.05** |
| fling `LuauUI/mount` | 1.52 ms/f | **~0.80–1.24** |
| steady `LuauUI/mount` | 0.626 ms/f | **0.572** |

Across this whole pass the surface went **249 → 178 instances (−28%)**.

### Verified

- Full suite **3 413**, RascalRally **3 089** — and **no test assertion was changed**.
  Three source-shape probes grep a fixed window after a function signature and my guards
  pushed the asserted lines out of it; rather than widen the windows to fit the code, the
  guards were compacted to one line and the rationale moved above each function.
- **All ten lab workloads pass at 360×691 with the layout audit armed**, which is the
  check that catches a node in the wrong place.
- Teardown still returns to the overlay only — an elided handle that leaked a record
  would show as a residual instance and does not.
- Screenshot verified: avatars, labels, toggles, steppers, buttons and row plates all
  present and correctly positioned.

**Rollback: `opts.elideContainers = false`** restores an engine object for every node.
Kept deliberately — this changes which instances exist at all, and a consumer debugging a
layout in the Explorer may want the full tree back.

**A caution for the next reader**: the headless suite barely exercises this. Almost every
test drives `fake_target`; `screen_target` is engine-only, so the real verification here
was Studio, not the 3 413. Treat a green suite as necessary and nowhere near sufficient
for adapter changes.

---

## L-22 — incremental `structuralSync`: the premise was wrong, measured before building

**Not built. The task's premise does not survive measurement, and this records why.**

`structuralSync` was the top remaining lever on the strength of one observation: `mount`
tracks live row count (6 rows 0.66 ms/f → 13 rows 0.97 ms/f) while churn per scroll step
looked constant, which is the signature of an O(all live nodes) sweep. Instrumenting the
pass instead of reasoning about it:

**55 structural passes over a 200-step steady scroll, 2.166 ms each:**

| phase | ms/pass | share |
|---|---|---|
| `ensureTree` | **1.525** | **70%** |
| the retiring sweep | 0.357 | 16% |
| `syncZOrder` | 0.192 | 9% |
| `livePaths` | 0.068 | 3% |
| retire collection | 0.023 | 1% |

`ensureTree` both walks and creates, so the two were separated:

```
nodes visited per pass     148
of which NEW                19.1        (129 visits do nothing)
raw Instance.new share      0.237 ms
per NEW node setup          ~83 us      (against ~12.4 us for a raw Instance.new)
=> the no-op walk is ~0.13 ms of a 2.166 ms pass — about 6%
```

**Making the pass incremental targets ~6% of it.** The cost is not the traversal; it is
the ~83 µs of setup each genuinely new node needs — `applyProps`, handler wiring, chrome —
of which the raw engine allocation is only 12.4 µs.

**And the original observation had a different cause.** `mount` scaling with row count is
not a sweep: the wide row's pitch is 56px against the compact row's 152px, so a scroll of
the same distance crosses **more row boundaries** on the wider viewports. More visible
rows meant more churn per step, not more walking. A correlation read as a mechanism.

### What this leaves

The remaining lever is the ~83 µs per new node, and three passes have already gone at it
from different directions — recycling (avoids `Instance.new`/`Destroy`), the property diff
(writes only what changed on adoption), and inert-container elision (34% fewer objects to
set up at all). What is left is handler wiring and chrome construction on the nodes that
genuinely are new.

**Kept from this pass**: the six `structuralSync` phase timers, published through
`controller.stats()` as `ssTotal`/`ssEnsureTree`/`ssSweep`/`ssZOrder`/`ssLivePaths`. They
cost six `os.clock` calls per structural pass and they are what turned a plausible story
into a measured one. The per-node visit counters used to get the split were removed —
those did cost a table write per node per pass.

---

## L-23 — the director's ornate-theme report: reproduced, and three defects behind it

The report: *"some buttons were so small the single glyph overflowed onto the border
area."* Chasing it found three separate problems, only one of which was the one reported.

### 1. Every perf measurement in this pass was taken on the FLAT theme

Asked directly whether any perf work had been done with a theme loaded: **no.** Worse,
`select:theme=X` **recorded the name and never applied it** — only the `themeSwap`/
`themeCost` passes ever installed a package. So a run could select `fantasy_ornate`,
mount, and measure a flat surface, while `steps.export` wrote `theme = settings.theme`
into the capture row. **A capture that names a theme the surface is not wearing is not a
comparable measurement, it is a wrong one.** Fixed: one `applyThemeByName` shared by the
selector and the passes, which also **refuses a theme it cannot compile** rather than
silently falling back.

### 2. Re-measured with the theme actually on

| | flat | fantasy_ornate |
|---|---|---|
| GuiObjects | 91 | **181** |
| total instances | 178 | **280** |
| `ImageLabel` | 25 | **100** |
| `Frame` | 9 | **9** |
| **containers elided** | **46** | **46** |

**Elision holds identically under a rich theme** — decoration hints attach to controls,
not to layout containers, so the 46 elided nodes are elided either way. That was the
thing most at risk from this question and it survived.

### 3. The reported defect, and why nothing caught it

A 60×46 `Open` button: its own `Text = "Open"`, `TextBounds = 36×18`, `TextFits = true`.
The solver sized the control for that label and filed no finding. The **theme then lifted
the label into `LuauUIChromeText`, sized from the ART** — a 36px decoration minus two
14px corner pieces — leaving a box **8px wide**. The label rendered as nothing.

This is the *painted at a size nobody measured for it* family the project already has a
lesson about, reaching the one seam the layout audit cannot see: **the lift happens in
the adapter, after the solve.** `controller.diagnostics()` returned zero for a screen with
no readable button labels.

`chromeArtCensus` now checks it, and the check took two attempts:

- **v1 compared the box against `lifted.TextBounds` and flagged nothing.** A label
  truncated to nothing reports `TextBounds.X = 0`, so "box narrower than text" was never
  true for exactly the labels that had vanished — the same trap as `TextFits` returning
  true for a truncating label. **`TextBounds` is the rendered width, not the required
  one.**
- v2 takes the requirement from the HOST's own measured text — the width the solver sized
  the control for — and separately flags `vanished` when a non-empty label renders zero.

Live result: **ornate 8 of 34 lifted labels flagged**, including `Open` at
`boxW = 8, wantW = 36, vanished = true` and overlay chips at `boxW = 98, wantW = 126`.
**Flat: 0 of 0.** v1 reporting 0 on the same screen is the mutation evidence.

### What this does and does not do

It **surfaces** the defect; it does not repair the geometry. The fix is a contract
change — a theme's chrome content area must be able to hold the label the solver measured
the control for, or the control must grow — and that belongs in its own pass with the
theme packages in scope. What has changed is that it can no longer ship unseen.

---

## L-24 — the second half of the ornate report: the frame is narrower than the control

The director's follow-up — *"the avatar image and another part of each row was
overflowing too"* — is a different defect from the vanished label, and the measurement
separates them cleanly.

**Nothing is overflowing.** Two engine-space sweeps found zero: no LuauUI node outside
its path-parent (61 nodes), and no adapter-owned decoration outside its host (115
checked, after excluding clip hosts — a scrolling canvas legitimately exceeds its
viewport, and the first sweep reported ten false positives for exactly that reason).

**The decoration is UNDERSIZED.** Ten of seventeen decorated nodes carry a primary
chrome layer smaller than the control it frames:

| node | control | decoration | uncovered |
|---|---|---|---|
| `/Row/Hit` | 336×152 | 312×152 | **24 × 0** |
| `/Row/Row/Controls/Open` | 60×46 | 36×46 | **24 × 0** |

**Exactly 24px on X, 0 on Y, regardless of control size** — a constant, so it is an inset
applied to the wrong box. 24 is the host's own horizontal `UIPadding` (`space.s + 4` per
side); Y is clean only because these controls have no vertical padding.

**Cause.** Roblox's `UIPadding` shrinks a host's ENGINE children, so a decoration
parented to a padded control is inset by that padding unless something adds it back.
`applyFullBleed` does precisely that — and it has **one call site**, which the layered
`chromeStack` path does not use. The content then sits outside the painted frame, which
is what the director saw: the avatar, the labels and the value row all outside the ornate
border while every one of them is correctly inside the control's own box.

`chromeArtCensus` now reports `undersizedDecorations` beside the lifted-label check.
Neither repairs the geometry — both make it impossible to ship unseen.

### Why two sweeps were needed, and the instrument lesson

The first overflow sweep compared every node against its path-parent and reported ten
overflows, all of them rows below the fold inside the scrolling canvas. **A clip host's
children are supposed to exceed it.** An instrument that does not know which containers
clip will report every scrolling list as broken — and would have sent the next reader
chasing a defect that is not there.

---

## L-25 — the ornate geometry, fixed: two bugs, one mistake, made twice

Both defects were the same mistake in two places: **a `UIPadding` on the host shrinks its
engine children, and neither path added it back.**

### Fix 1 — layered decorations were never full-bleed

`applyFullBleed` exists precisely for this and had **one call site**: the
single-decoration path (`LuauUIChrome`). Layered packages name their layers
`LuauUIChromeL<N>` and took a different route, so every layered theme drew its frame
short by the host's padding.

Now applied to stack layers too, skipped when the layer sits inside a mask (the mask is
the full-bleed surface then) and when the layer is not scale-1 on both axes.

### Fix 2 — the lifted label subtracted the padding a second time

`liftGeometry` was handed `rect.w - padX` and then inset the recipe's `contentInsets` on
top, against a box that the engine had *already* shrunk by the same padding. A 60px
button: `60 − 24 (padding) − 28 (recipe) = 8px`, and the label rendered nothing.

Now the host's own box goes in, and the lift is full-bleed first and inset second —
reusing the same `chrome_slots.fullBleedBox` helper. The plaque path is deliberately
excluded: a plaque rect is already the absolute box the recipe declared, and compensating
it would push the title off its own plate. That exclusion is pinned by a test.

### Measured live, `fantasy_ornate`, 360×691

| | before | after |
|---|---|---|
| `Open` decoration | 36px on a 60px control | **60px** |
| `Open` lifted label box | 8px | **32px** |
| ...what it actually rendered | **0px — nothing** | **29.5px** |
| undersized decorations | 10 of 17 | **0 of 46** |

On screen the labels are back: `Op…`, `Run…`, `Mou…`, `Res…`, `▶ Run…`, and the frames
now cover the controls they belong to.

### The residual, characterised precisely

Eight lifted labels are still short — **every one by exactly 4px**, regardless of control
size or label length. Constant, so it is not "the border was never reserved" (that would
be ~28px). It is the recipe asking **14px per side** while the solver reserved the
control's own padding of **`space.s + 4` = 12px per side**: 2px short each side.

The measure seam already has the machinery (`chromeInsets` composed into `toLayoutNode`);
what it does not do is add the recipe's inset ON TOP of the node's own padding for this
slot. That is a third, separate defect with a known shape, and it belongs with the
measure seam rather than the paint seam these two fixes live in.

Suites unchanged: LuauUI 3 421, RascalRally 3 089, gate PASS 22/22.

---

## L-26 — the residual 4px: the measure seam was never wrong, the lab wore half a theme

L-25 left eight lifted labels short by **exactly 4px** and read it as a third defect at
the measure seam: "the recipe asks 14 per side, the solver reserved the control's own
12". The arithmetic was right and the location was not. **The measure seam adds the
recipe's inset ON TOP of the node's padding and always has** — solved headless, one
content-sized `Open` button, Studio Neutral vs fantasy-ornate: **69px → 120px**, a 51px
difference that is the 28 of `contentInsets` plus the theme's own type ramp. There was
nothing to fix there.

### What was actually happening

The perf lab installed the **decoration half of a theme and not the metric half**.

```
applyThemeByName(name)
  ctx.themeChrome.setPackage(pkg)   -- = adapter.setThemePackage: the ART
  -- and nothing else
```

The metric half is the resolved snapshot published as `themeMetrics`, which is the fact
the solver reads and the only thing that makes a recipe's `contentInsets` reserved
rather than merely painted. It was never committed. So the adapter painted
fantasy-ornate onto a surface the solver had measured with Studio Neutral, and the paint
seam then lifted every label by 14+14 of inset the layout had never been told about:

```
box  = host - 28   (the recipe's contentInsets, taken at paint)
want = host - 24   (Studio Neutral's buttonPadding, all the solver reserved)
                     -> short by 4px. Always. Every size, every label.
```

Constant because both terms are constants — which is exactly what the L-25 measurement
said and exactly what should have pointed here rather than at the solver.

### The live tell that names the cause in one number

| | before | after |
|---|---|---|
| `Open` **TextSize** | **18** — Studio Neutral's `control` | **17** — ornate's |
| `Open` rect | 60 x 46 | **83 x 67** |
| lifted label box | 32px (text needs 36) | **55px** (text needs 30.5) |
| `▶` cycler glyph box | 8px, `vanished = true` | **37px** |
| `liftedTooSmall` | **8** of 34 | **0** of 31 |

A themed surface whose text is measured at the *neutral* package's size is not a themed
surface. Every ornate number in L-23 — 181 GuiObjects, 100 ImageLabels, the elision
survival — was taken on flat GEOMETRY with ornate PAINT, and should be re-read as such.

### The fix, and the two things it uncovered

`applyThemeByName` now installs through `theme_controller` — sheet derives, decoration
and `env:set("themeMetrics")` in ONE transaction (ADR-0019 §7) — with the
`themes.resolve` + `env:set` fallback for a controller-absent target. Never optional:
the metric half not landing is the whole defect.

With the theme actually reaching the solver, **the lab could no longer mount at all**,
and both refusals were correct:

1. **The one-line row overflowed its 56px slot by 19px at every viewport** and the
   compact row its 152px slot by 26. `rows.heightFor` took a viewport width and a type
   scale and no theme; a themed `control` carries a carved border the solver reserves as
   padding. Third input, same class as the first two.
2. **The compact controls line overflowed by 18px at 360px** and the overlay's cycler by
   105. An HStack does not compress on its main axis, so the Button and "Run all" each
   take their own line — the ruling the Stepper and the action grid already had.

**Every one of those terms is ZERO on a flat package**, so `rows.VERSION` is unchanged
and all eighteen recorded captures stay admissible: the workload they measured has not
moved. That is asserted as a test rather than as prose (`perf_lab.spec`, "the FLAT row
geometry is byte-identical").

### Carried, not fixed: a control whose text lives in a CHILD label is buried

Measured on the same screen. A Toggle's own text is a child `Label` at `ZIndex 1`; the
host TextButton's `Text` is `""`, so `LuauUIChromeText` lifts an EMPTY string and
`LuauUIChromeL1` — opaque, `ZIndex 1`, later in sibling order — paints straight over
"Ready" and over the `Track`. `liftedTooSmall` cannot see it: it skips an empty lift by
construction. Different family from this entry (nothing is mis-MEASURED; the geometry is
right and the z-order is not), pre-existing, and untouched by anything here.

Suites: LuauUI **3 426**, RascalRally 3 089, gate PASS.

---

## L-27 — the ornate MicroProfiler pass: the focus map was 20% of every scroll frame

First profiling pass taken with a theme **actually installed** (L-26 established that every
previous "ornate" number was flat geometry with ornate paint). Two targets, per the
director: presentation (scrolling) and layout computation (resizing).

### The instrument came first, because the old one needed a human

The nine phase scopes were readable only by pressing Ctrl/Cmd+F6 and eyeballing a
MicroProfiler dump — which makes the optimization loop manual at exactly the step that has
to repeat. `profile.setHooks` is the seam that fixes it: the SAME scopes, timed with the
wall clock, exposed as a new `scopes:<pass>` step that reports inclusive and exclusive ms
per scope. The headline ms still comes from the pass's own clock with the hooks off — the
hooks cost two `os.clock()` calls per scope and the scope counts run to six figures, so
these numbers are for ATTRIBUTION, never for a capture row.

**It was wrong twice before it was right, and both were the same class of error.**

1. **One stack shared across threads.** The pass body runs on the caller's coroutine and
   waits a Heartbeat between steps; the lab bootstrap opens `scenario` on the Heartbeat
   connection's own thread every frame. Interleaved, they charged phases to the wrong
   parent. Now one stack per `coroutine.running()`, which is what `debug.profilebegin`
   already does.
2. **Exclusive time accumulated on the way IN.** `parent.child += now - parent.mark` adds
   the parent's OWN self time, not its children's — so for every scope WITH children the
   two numbers were swapped. `scenario` reported 2.15 ms/frame of exclusive work while its
   entire body is two calls that are both scoped. It now accumulates on the way out
   (`parent.child += total`), and `scenario` reads 0.4 ms — as it should.

   **Leaf scopes were correct in both broken versions**, which is exactly why a reading
   survived twice. A number that is right for the simple case and wrong for the nested one
   looks like a measurement.

Two scopes were added to close the blind spot the first honest reading exposed:
`LuauUI/present` (the per-frame presenter refresh, which runs whether or not anything
changed) and `LuauUI/focusmap`, plus `LuauUI/tick`. None of the nine could see any of it,
because they only open when there is layout work to do.

### The finding

`presenter.refresh()` re-derived the **entire focus map** — a full tree walk, plus a
second walk for the traversal rank, per presented surface — **every frame, unconditionally**.

| ornate dense-scroll, 500 rows, 360x691, 120 frames | before | after |
|---|---|---|
| `LuauUI/focusmap` | **78.4 ms** (478 derivations) | **7.6 ms** |
| all LuauUI work | 3.22 ms/frame | **2.63 ms/frame** |
| `scrollSteady` step p50 | 0.890 ms | **0.53 ms** (3 reps: 0.523/0.531/0.558) |
| `scrollSteady` step p95 | 1.456 ms | 1.28 ms |

Flat is the same story (74.0 → 10.7 ms), so this was never a theme cost — it was 20% of
every scroll frame in every configuration.

### The fix, and the line it does not cross

A `structureEpoch` on the controller, bumped by exactly what can change the derived map:
a structural sync, a change in the HIDDEN-root set (a `ViewThatFits` candidate losing at a
new width does that with no structural churn at all), and a `navigation`/`semantics` dirty
class. That last one is read off the SCHEMA rather than a hand-kept prop list — `focusable`
declares `dirty = { "navigation" }` and `enabled` declares `semantics`, and both decide
whether a node is in the order. Omitting it turned two suite tests red immediately
("re-enabling restores focus reachability with no remount"; "navigation skips a disabled
Slider's track"), which is the mutation evidence that the epoch is complete.

**Only the DERIVATION is cached; the graph call is still made every frame with the same
arguments.** `replaceGroups`/`setOrder` are not pure — on the topmost scope they re-seed
focus when the current path has left the order, and that re-seed is load-bearing for the
passive/resign behaviour this project spent seven director rounds getting right. Skipping
the walk is safe; skipping the call is not.

### Layout computation: measured, diagnosed, NOT fixed

The resize path barely moved (p50 8.33 → ~7.7 ms, near noise) because the focus map was
never its bottleneck. What is:

| ornate resizeStorm, 12 steps | exclusive |
|---|---|
| `arrange` | 69.6 ms (n=131) |
| `commit` | 26.6 ms (n=169) |
| `measure` | 24.3 ms (n=131) |
| `mount` | 22.9 ms (n=23) |

**One viewport change costs 5 solves and 2 structural syncs**, reproducibly (measured on a
width-only resize: 5 solves, 22 removes, 16 creates, 16 park refusals, 6 recycled).
`arrange` + `measure` are 56% of the pass and 78 of the 131 arranges re-enter from `react`.

**And the shipped incremental layout is inert here: `incremental=on` produced 2 partial
solves out of 65.** `arrangedPerDataChange` moves 85 → 78.6 and `resizeP50` does not move
at all. That is not a contradiction of the ~17x recorded earlier — it is what incremental
layout means: it skips subtrees whose constraints did not change, and a resize changes
every constraint by definition. The lever for a resize is the solve COUNT, not the solve.

### The next lever, with its measurement

**A themed node cannot be recycled.** `isBare` refuses to park any handle carrying a
decoration, a chrome lift, or child instances — which is every control under a skinned
package. Measured: `mount` costs **5.44 ms/call under ornate vs 2.02 ms/call flat**, 2.7x,
and it is now the largest single scope in a scroll frame (98 ms of 316). Every previous
recycling measurement — including the one that shipped it OFF as "indistinguishable from
noise" — was taken on the flat theme, where there is nothing to recycle that is expensive.

Not attempted here: it needs `park`/`adopt` to re-key the chrome children and re-sync the
plan for the new path, in the most defect-prone area of this codebase, and it deserves its
own round with the visual-diff harness rather than a rider on a profiling pass.

### The idle frame, which nothing was measuring

Every pass in this lab drives something, and `idle-baseline` measures the place with
NOTHING mounted — so neither answered the question that decides whether a HUD is
affordable: what does a mounted, untouched surface cost per frame? A game screen is
mounted for the whole session and touched for a fraction of it. New `idle` pass.

| ornate, 500 rows, 360x691 | ms/frame |
|---|---|
| before this pass (derived: focus map 0.164 ms x 2 surfaces) | **~0.48** |
| after the focus-map cache | 0.180 |
| after caching `syncContributions` too | **0.124** |

`syncContributions` is the same defect as the focus map, one line above it in `refresh`:
a full pre-order walk per surface per frame, whose own doc calls it "cheap by
construction: one pre-account walk" — true per call, false per second. It is gated on the
same epoch. On an idle frame `present` fell 12.31 → 4.24 ms per 120 frames (-66%).

**The idle frame moved from OVER the 0.4 ms device target to 3.2x inside it.** That is the
number that matters for a HUD: it is paid on nearly every frame of a session.

### Instance recycling is worth -32% flat and NOTHING under a theme

Measured directly, `scrollSteady` step p50, 500 rows, 360x691:

| | recycle=on | recycle=off | delta |
|---|---|---|---|
| flat | **0.266 ms** | 0.394 ms | **-32%** |
| fantasy_ornate | 0.514 ms | **0.489 ms** | **+5% (a small LOSS)** |

Under a skinned package the park/adopt bookkeeping costs slightly more than it returns,
because the nodes it can actually park are the cheap bare ones and every expensive one is
refused: 249 refusals against 96 parks. This is the measured size of the themed-recycling
prize — roughly the -32% flat already gets — and it is also a caution that the feature as
it stands is not free on a themed surface.

Suites: LuauUI **3 430**, RascalRally 3 089. All ten workloads swept clean under
`fantasy_ornate`.

### A note on module size, found by hitting it — and resolved

`src/present/presenter.luau` reached **200 609 characters** (4 633 lines, 30% comments) and
Roblox refuses a script-driven `Source` assignment at 200 000. `ScriptEditorService:
UpdateSourceAsync` still accepts it, so tooling has a route, but the simple one is gone.
Three more modules are in the same class: `screen_target` 187k, `renderer` 173k,
`chrome_slots` 122k. Nothing here is broken by it; it is recorded because a hard platform
ceiling reached by accident is worth knowing about before it is reached by surprise.

**Resolved 2026-08-06 by extraction, not by a general split.** The file was not a blob:
lines 1-1060 were module-level PURE helpers and lines 1061-4633 were a single closure
(`presenter.new`, 78% of the file) whose parts all share upvalues. Only the first part is
safely movable, so only that moved:

- `src/present/focus_map.luau` (24 KB) — focus order, the linear traversal rank,
  navigation groups (`autoGroups`/`layoutGroups`) and the contribution walks that feed
  them. One dependency: `input/contribution`.
- `src/present/modal_zones.luau` (4.7 KB) — the modal outside-tap two-zone geometry.

`presenter.luau` is now **177 148 characters**, back under the ceiling with ~23 KB of
headroom, and plain `Source` assignment works again.

**The closure was deliberately NOT split.** Doing so means converting upvalues into an
explicit passed-around state record — a large mechanical refactor with no functional
payoff, in the code that produced three separate defects in this stage alone (the chrome
z-ladder, the forward-declaration trap, the parent/child timing inversion). Two lessons
in `docs/lessons/` already cover what that refactor would poke.

Two things kept the risk at a file move rather than a refactor: the moved bodies are
byte-identical (exports are listed at the bottom of each new module rather than written
as `function M.x`, so no internal call site changed), and the presenter re-binds every
export to its ORIGINAL local name — so not one line of the 3 500-line closure changed.

Two real breakages surfaced and were fixed: `modal_zones` needs `FOCUSABLE` (it borrows
it from `focus_map`; no cycle) and `FOCUS_ORDER_SCHEMA` had to be exported for the
presenter's focus-order dump. Both were caught by the suite immediately — 13 failures,
then 3 430 green. Live after the move: `focusTraverse` visits 40 stops, `liftedTooSmall`
and `undersizedDecorations` both 0, idle 0.109 ms/frame, scroll p50 0.458 ms, all ten
workloads swept clean under `fantasy_ornate`.
