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

---

## L-28 — themed instance recycling: park releases the chrome, adopt re-keys it

L-27 measured the refusal: `isBare` refused any handle carrying a decoration, a chrome
lift, or child instances — which under a skinned package is every control by
construction (ornate paints 5-11 chrome children per control). So recycling delivered
-32% on flat, where there is nothing expensive to recycle, and a small LOSS under
`fantasy_ornate` (249 park refusals against 96 parks), where `mount` runs
**5.44 ms/call** and was the largest single scope in a scroll frame.

### The fix, in five rulings

1. **Eligibility widened from "bare" to "nothing that cannot travel".** Chrome is
   handle-keyed; its only path-keyed state is the `instancesByPath` registration. Still
   refused, each for a stated reason: clip-host ROLE, presentation transform, motion
   scale, the sibling-parented hit expander and float focus ring, a focused handle.
2. **ONE enumeration of the chrome's path-keyed children**
   (`screen_chrome.chromePathChildEntries`): the single decoration, the lifted label,
   the managed icon, the layer ladder *including a masked layer's CanvasGroup* (its
   ImageLabel is parented to the mask, not the host — direct-children iteration could
   never find it), bar window/fill/ornaments, and the toggle's Track/Knob. `park`
   releases exactly this set and `adopt` re-keys exactly this set, so the two seams
   cannot drift — the defence against this area's recurring
   ruling-at-one-call-site defect (applyFullBleed, the chrome z-ladder). A spec pins
   every family name inside the function body.
3. **A hint mismatch REFUSES the adoption — it never re-plans.** The decoration hint
   arrives through `create` and no later setter re-plans it (pinned invariant); a
   re-plan on adopt would be a second planning path AND a rebuild, which costs what the
   fresh create costs — a mismatch adoption is never a win. Content, never address
   (`chrome_slots.hintKey`, one ruling shared by the renderer's pool bucket, the fake
   target and the live adapter): the renderer rebuilds cell blueprints every window
   slide, so `tostring(hint)` in the old bucket key made every hinted node's bucket
   unreachable — measured zero hinted adoptions, ever. `adapter.adopt` now takes the
   incoming hint as its 4th argument.
4. **A chrome EPOCH gates staleness, not a reconcile.** A parked handle has left
   `handlesByPath`, so neither `setThemePackage`'s every-handle resync nor the asset
   fallback refresh can reach it. `chrome_slots` state now carries one integer bumped
   by exactly the facts a chrome plan depends on (package swap, asset-ledger movement);
   park stamps it, adopt refuses on mismatch. The first version called `syncChrome` on
   every adoption instead — correct, but it charged every adoption to heal a case that
   is rare by construction; the epoch check is one compare.
5. **`discardParked` is now the census-correct teardown** (a parked node's chrome stays
   COUNTED while parked, so every census must fall on discard), and a parked handle's
   `path` is a sentinel (`\0LuauUIParked`) so the teardown helpers' internal
   `instancesByPath` clears can never clobber a successor node's registrations at the
   old path.

### Measured, live, ornate dense-scroll 500 rows 360x691, interleaved A/B

| per 120-frame scrollSteady pass | recycle=on | recycle=off | delta |
|---|---|---|---|
| `LuauUI/mount` inclusive | **53.5 / 60.4 ms** | 102.0 / 114.7 ms | **-45%** |
| all LuauUI work (sum of scope exclusives) | **143.2 / 153.8 ms** | 191.2 / 209.1 ms | **-26%** |
| `LuauUI/present` inclusive | 127.8 / 137.5 ms | 177.4 / 194.4 ms | -28% |
| `scrollSeek` worst step | 24.1 ms | 27.7 ms | -13% |
| `scopes:idle` total | 10.5-11.9 ms | 11.0-12.9 ms | no cost |

Park refusals under ornate fell from 249-vs-96 to **elided nodes only** (~1 240
refusals ≈ the 44% of creates that are elided and own no engine object — a free and
correct refusal); 1 426 parked, 1 362 recycled in the first measured session.

### The instrument finding: step p50 cannot see this win

`pass:scrollSteady` `stepMs` p50 moved nowhere (on ≈ 0.50, off ≈ 0.45 ms) — and a
same-session FLAT control shows the same nothing (0.39 vs 0.38), so L-27's
"-32% flat p50" no longer reproduces on today's build either. The step timer measures
the scroll write + re-window bookkeeping only; `mount` runs under `LuauUI/present` on
the Heartbeat, outside the step — so the step p50 pays the retire-path bookkeeping
(park + prop capture, ~+0.05 ms on the on-side median) and can never see the adoption
saving, which is 5x larger on the same frames. The honest comparator is the scope
totals above. (Same lesson family as measure-the-requirement-not-the-render: an
instrument that does not contain the cost cannot report the saving.)

### Verified beyond the counters

- **Engine visual diff, on vs off, same drive (steady + seek + steady):** 424 nodes,
  **1 difference — the lab overlay's own scope-counter text**. The recycled surface is
  engine-identical.
- `counters().chromeArt`: `liftedTooSmall` 0, `undersizedDecorations` 0 in every
  configuration; `decoratedNodes` 40 at rest / 53-54 under churn — never falls. The
  chromeArt census reads decorations *through* `instancesByPath[path .. "/" .. name]`,
  so its finding 54 decorated nodes after 5 306 recycles is itself the proof that
  adopted chrome is reachable at its new paths.
- All ten workloads swept clean under `fantasy_ornate` with recycle=on (lifecycle-soak
  recycles 0 by design: the pool drains on unmount).
- Hard-scroll screenshot human-checked: every recycled row wears its OWN chrome —
  frames sized to their controls, toggle art on the toggle, no ghost decorations.
- Suites: LuauUI **3 442** (new `instance_recycling_themed.spec`: hinted nodes recycle
  across a slide, differential on/off byte-identical, hint-mismatch refusal both
  directions, epoch moves on ledger movement and not on no-ops, plus source contracts
  on the live adapter), RascalRally 3 089, gate 22/22 PASS, `check_flat_baseline` PASS.

### Verdict and residuals

**Recycling stays ON by default, now for themed packages too** — it went from a
measured +5% loss under ornate to -26% of all LuauUI scroll work, with the win
concentrated in `mount`, exactly where L-27 located the prize.

Residuals: (1) the retire path adds ~0.05 ms to the step-side median on churn frames —
repaid ~5x by the mount saving on the same frames, recorded so nobody rediscovers it
as a regression; (2) the pool can hold up to 64 chromed instance trees off-screen
(unparented, so invisible to the GuiObject census) — bounded by the existing cap;
(3) a RascalRally Studio canary is owed — the game place was not open this session;
the framework suite, the game suite and the engine visual diff all pass, and no
public contract moved (adopt's 4th argument is adapter-internal, feature-detected).

## L-29 — one viewport change is one solve (L-27's lever, paid)

**Date:** 2026-08-13 · **Commits:** `8560f2b` (framework), `0c3f507` (lab)
**Evidence tier:** **2 — confirmed on the real Roblox engine**, not only headless
(see "Tier 2 confirmation" below) + the tier-3 device capture that priced it
(`rr.html`: arrange 8.270 ms/occurrence, measure 3.057 ms/occurrence, 9.67
arranges/step, arrange+measure = 58.5% of wall).

L-27 recorded *"one viewport change costs 5 solves and 2 structural syncs,
reproducibly"* and concluded **"the lever for a resize is the solve COUNT, not the
solve."** This entry pays it.

### The five were TWO multipliers, compounding

1. `src/client/roblox_env.luau` `pushViewport()` writes **six** facts on one real
   resize — `viewportRect`, `coreSafeInsets`, `deviceSafeInsets`,
   `topbarSafeInsets`, `topbarInset`, `displaySize`. Written loose, each is its
   own flush.
2. `src/render/renderer.luau` observed **eight** geometry keys *independently*,
   each callback running a full `solveAndApply()`. And `typographyScale` is a
   *memo over* `displaySize` + `preferredTextOffset` — so even a single loose
   write fired twice.

### The fix, and why both halves were required

`env:batch(fn)` (delegating to the core's existing `core:transaction`) on the
adapter's three fact-groups, plus **one scope-owned memo** over all eight keys in
the renderer. The core is glitch-free, so that memo recomputes at most once per
flush however many dependencies moved.

Measured on a 40-row tree, one width-and-class-changing resize:

| configuration | solves |
|---|---|
| six loose writes + eight observers (as shipped) | **5** — L-27's number exactly |
| batching alone | 5 |
| one coalescing memo alone | 4 |
| **both** | **1** |

Neither half works alone: batching does nothing while N observers each solve, and
coalescing does nothing while the writes are N separate flushes.

### Tier 2 confirmation — the real engine, the real adapter

Measured 2026-08-13 in Studio (`LuauUI-PerformanceLab.rbxl`, Client datamodel),
against a live `screen_target` adapter painting real Instances, on the *pre-fix*
source that place still holds — the only place that could still measure the
defect rather than its absence. Same 40-row tree, same six writes:

```
viewportRect ALONE:       1 solve(s)
the adapter's SIX writes: 4 solve(s)  (360x691)
the adapter's SIX writes: 5 solve(s)  (1200x800)
the adapter's SIX writes: 5 solve(s)  (390x844)
```

Identical to the headless numbers and to L-27's record. So the count was never a
Lune artefact, and `viewportRect` alone really does cost 1 on the real engine
too — the multiplier was always the other five facts meeting eight independent
observers.

### Traps worth keeping

- **Headless did not reproduce it.** A bare `env:set("viewportRect", …)` costs
  exactly 1 solve, at every size and across every size-class boundary. The 5 only
  appear once you mimic what the **real adapter** writes. When a device number
  will not reproduce headless, suspect the adapter before the framework.
- **`core:memo` must be `scope:own(...)`-ed.** An unowned memo is a live registry
  node after dispose; it turned **24** registry-neutrality specs red at once.
  That suite is the tripwire for this class.
- **A compressed `.rbxl` is not a greppable oracle.** Probing the built binary for
  `geometryFacts` returned 0 occurrences while the fix was demonstrably in it;
  building the same project to `.rbxlx` showed 2. Any past claim of the form "the
  built bytes contain/lack X" taken from a binary place file is unsound.

### Residual, quantified — the overlay's reservation dance

Instrumenting the lab's resize pass surfaced a second, independent cost. Over 4
resize steps the watched facts fired: `viewportRect` 5,
`deviceSafeInsets`/`topbarSafeInsets`/`topbarInset` 4 each, `displaySize` 1 — and
**`coreSafeInsets` eleven**.

The lab's overlay owns that edge: `forgetReservation` zeroes it whenever
`viewportRect` or `typographyScale` moves, then `onGeometry` republishes the
measured dock height. That is **two extra unbatched writes per resize**, each its
own flush and so its own solve — roughly **3 solves per resize step** in the lab
rather than the 1 the framework now costs.

This is a *measure-then-publish feedback loop*, not a framework defect: any app
that reserves space from measured geometry will have the same shape. It is left
open deliberately — the honest fix is for a measure→publish cycle to settle inside
one flush, which is a design question, not a patch. `tests/perf_lab.spec.luau`
excludes `coreSafeInsets` from its batching oracle for exactly this reason and
says so, so the next reader does not mistake the dance for a batching regression.

### L-29 residual 2 — a presented MODAL still costs two solves per geometry change (CLOSED 2026-08-15; the title is the misdiagnosis, see the end of the entry)

Found by the Rascal Rally consumer rider (`games/RascalRally/code/tests/luauui_resize_solve_contract.spec.luau`,
game commit `1fb175a`) while proving the coalescing on a production surface.

A plain surface costs **1** solve for one batched six-fact rotation, as L-29
above. The shipped **role-pick modal**, built and presented exactly as the game
builds it, costs **2** — and it is 2 *whether or not the rotation crosses a size
class* (probed both ways: 1920x1080 → 691x360 crossing, and 1920x1080 →
1900x1000 not crossing; both 2). So the second solve is **not** the adaptive
size-class rebuild, and it is not per-key fan-out either — the fan-out is gone.
It is a second solve site on the **modal presentation path**.

Not chased here, and deliberately not guessed at: `src/present/presenter.luau`
was being edited concurrently by another task, and a mechanism claimed without
measurement is exactly what this log exists to prevent. The rider asserts a
CEILING of 2 rather than an equality of 1, so the modal's own second solve can be
removed later without the check needing to move, while a return to per-key
fan-out (~5) still reddens immediately.

Next step when picked up: instrument the four `solveAndApply()` call sites in
`src/render/renderer.luau` with a call-site tag and drive one rotation against a
presented modal — the same probe technique that found L-29, which took about ten
minutes and replaced a plausible story with a number.

**CLOSED 2026-08-15, and every attribution above is wrong.** The recipe worked;
what it found was not a modal. Full write-up, transcripts and mutation evidence:
`artifacts/swiftui-parity-round3/o20-modal-solve-residual.md` (LuauUI owed row
O-20).

  * **It was never the presentation path.** `presenter.present` of the same
    blueprint costs exactly what `presenter.presentModal` costs, and a modal over
    a plain 12-row tree costs **1**. Nothing in `src/present/` was involved.
  * **It was never 2 either.** 2 is the FIRST rotation of a freshly presented
    surface; the steady state was **3** (measured 2, 3, 3, 3 over four
    rotations). The rider could not see that because it measured one rotation.
  * **The trigger is a LAYOUT prop bound to a memo over the viewport.** The
    role-pick modal's two CTA sub-labels bind `width` to
    `{ type = "fixed", px = … }`, and the memo hands back a fresh table equal BY
    VALUE to the last one — the identity-not-value republication class L-29's own
    fix was built around, one layer down (a node prop rather than an env fact).
  * **The framework charged two extra FULL solves for that one prop write**, and
    both are fixed in `src/render/renderer.luau`: `feedbackArmed` outlived the
    flush that set it (THE ARM DOES NOT OUTLIVE ITS FLUSH), and `refresh`
    re-solved for `measure` dirt a settle-phase solve had already consumed (THE
    STALE-LAYOUT-DIRT TEST).
  * **A second, unbooked defect fell out of the first.** The leaked arm also
    promoted the first bound-value change after ANY geometry change from an
    incremental solve to a full one — 101 arranged nodes where 8 were needed, on
    the very fixture `tests/perf_principles.spec` uses to guard incremental
    layout. It could not see it because `stats().lastArranged` reports the last
    solve of a frame, not every solve in it.

Shipped: **1, 1, 1, 1** per rotation on the shipped role-pick modal, tier 1
(headless Lune). A device price for this has NOT been taken; L-30's device tiering
applies to L-29, not to this closure.

---

## L-30 — L-29, priced on the device: the count dropped, the solve did not

**Date:** 2026-08-14 · **Evidence tier: 3 — physical device**, and therefore
authoritative over every tier-1/tier-2 number in L-29.
**Captures:** `resize.html` (`resize-relayout` → `resizeStorm`) and `mount.html`
(`mount-ramp`), Samsung SM-A102U1 / Android 11 / 1 708 MB / Mali-G71, client 734,
taken with the **Profile** button so the window lands inside the chosen workload.
**Full analysis, method and per-scope tables:**
`artifacts/performance-stress-places/device-capture-2026-08-14.md`.

### The verdict: L-29 landed

| | `rr.html` (pre-fix, tier 3) | `resize.html` (post-fix, tier 3) |
|---|---:|---:|
| `arrange` **occurrences per step** | **9.67** | **7.12** (−26.4 %) |
| `arrange` ms/occurrence | 8.270 | **9.136** |
| `measure` ms/occurrence | 3.057 | **3.236** |
| `arrange` + `measure` share of wall | **58.5 %** | **50.8 %** |
| `react` (reactive flushes) per step | — | **3.03** |

**The per-occurrence cost did not move, and that is the pass condition, not a
disappointment** — `env:batch` plus the coalescing memo were aimed at the count.
+10.5 % on `arrange` and +5.9 % on `measure` are noise on a handset whose frame
time itself varies 129–204 ms.

**The −26 % understates it, because the workload got six times harder underneath
the comparison.** The pre-fix `resizeStorm` set `viewportRect` **alone**; the
post-fix pass drives the whole six-fact adapter group, batched as the adapter
batches it. So the honest line is **9.67 arranges/step for ONE fact, before →
7.12 for SIX facts, after.** On the pre-fix build those six facts cost 5 workload
solves (L-27's number, re-confirmed tier 2 in L-29); with two mounted surfaces and
the overlay's two extra writes the same step would have cost ≈ 15 arranges. That
makes the like-for-like win about **2×**.

**`react` is the direct device proof that batching is live.** Six loose writes plus
the overlay's two plus the data change is nine flushes per step; the device
measured **3.03**. The six-fact group arrives as ONE flush. No trace of per-key
fan-out; `geometry_solve_coalescing.spec.luau` is not owed an explanation.

### Where the time goes now (resize, 60-frame window, 173.2 ms/frame, 5.77 fps)

| scope | occ/step | total ms | ms/occ | % wall | worst ms |
|---|---:|---:|---:|---:|---:|
| `arrange` | **7.12** | 3 901.1 | 9.136 | **37.5 %** | **131.23** |
| `measure` | 7.12 | 1 381.9 | 3.236 | 13.3 % | 45.16 |
| `react` | 3.03 | 860.5 | 4.728 | 8.3 % | 28.26 |
| `mount` (structuralSync) | **2.00** | 766.4 | 6.387 | 7.4 % | 23.11 |
| `commit` | 10.15 | 726.1 | 1.192 | 7.0 % | 23.57 |
| `present` | 2.97 | 469.4 | 2.637 | 4.5 % | 15.61 |
| `focusmap` | 5.93 | 116.4 | **0.327** | 1.1 % | 4.23 |
| `mutate` / `tick` / `scenario` | ~1 each | 9.2 / 5.2 / 0.6 | — | 0.2 % | — |
| `resource` / `reset` | 0 | 0 | — | 0 % | — |

`RenderTotalTime` 22.87 ms against a 173 ms frame: **not GPU-bound, by 8×.**

### L-29 residual 1, quantified on the device — and it is the new top lever

The overlay's reservation dance is no longer an argument; it is two numbers.

* **`react` = 3.03 flushes per step** where the framework's own contribution is
  **1**. The other two are `forgetReservation` zeroing `coreSafeInsets` and
  `onGeometry` republishing the dock height. Every geometry flush re-solves every
  mounted surface, and `focusmap` = exactly 2 × `present` (356/178) proves there
  are two. `3 flushes × 2 surfaces + 1 data-change solve = 7`, against a measured
  **7.12**. So **≈ 4 of 7.12 solves per step (57 %) exist only because of the
  overlay's measure-then-publish loop.**
* **Roblox's own layout counters say the same thing from outside the framework.**
  `Root=LuauUI_PerfLabOverlay Relayouts=8 Updates=37 Resizes=38` against
  `Root=LuauUI_PerfWorkload Relayouts=8 Updates=73 Resizes=66`. **One dock panel
  provokes as many engine relayouts as the entire 2 000-row workload**, and 34 % of
  the updates. In `mount.html` the same panel takes 39 of 131 window-size relayouts.

Its *direct* time is small (~1–2 % of wall — a dock panel solve is cheap); its
*induced* time is two extra full workload re-solves per step, worth roughly
**−25 to −28 % of wall** to remove, i.e. a resize step going ~173 ms → ~125 ms on
this device.

L-29 left this open deliberately and was right to: the honest fix is that a
measure→publish cycle must settle inside one flush — `env:batch`/`core:transaction`
re-entrancy plus a settle phase in `src/core/custom.luau`'s flush, so a write made
*while responding to* a geometry change joins the flush that caused it. Patching
`perf_lab.luau` alone buys the lab a number and buys consumers nothing: every app
that reserves space from measured geometry has this shape.
`tests/perf_lab.spec.luau`'s `coreSafeInsets` exclusion is the regression test that
gets deleted when it lands.

### The other levers this capture ranks

2. **The solve itself is now the frontier.** `arrange` 9.136 ms/occurrence, 37.5 %
   of wall, **worst single occurrence 131.23 ms — 76 % of a whole frame in one
   call**, and 2.8× `measure` per occurrence, so the cost is rect derivation and
   stack distribution rather than text metrics. L-27's *"the lever for a resize is
   the solve COUNT, not the solve"* has been paid and is now **superseded**:
   incremental layout cannot help (L-27: 2 partial solves of 65 — a resize changes
   every constraint), so this is `arrange()` in `src/layout/solver.luau`, starting
   from the 131 ms tail rather than the 9.1 ms mean. A 30 % cut is −11 % of wall.
3. **Two structural syncs per viewport change, still.** `LuauUI/mount` = exactly
   **2.00 per step** at 6.387 ms = 12.8 ms/step, 7.4 % of wall. L-27 recorded
   "5 solves and 2 structural syncs"; L-29 removed the 5 and **left the 2**. A
   width change does not change the tree's structure —
   `src/render/renderer.luau:3460`. Halving it is −3.7 % of wall.
4. `commit` at 10.15/step (7.0 % of wall) is ~1.4 per solve and mostly falls out of
   lever 1; listed so it is not mistaken for an independent prize.

Recorded as healthy, not as a lever: `focusmap` at **0.327 ms/occurrence, 1.1 % of
wall** — L-27's `structureEpoch` cache holds up on a real device on the one
workload where every invalidation is legitimate.

### Traps and instrument findings worth keeping

* **The event log's timestamp column reconstructs engine scopes and NOT Lua
  scopes.** It reproduces `queuePresent` (30 pairs, 308.3 ms vs the aggregate's
  297.5 ms) and returns ~0.06 ms per `arrange` where the aggregate says 9.14 ms.
  So a `LuauUI/*` scope's per-occurrence *distribution* is not recoverable from a
  binary dump — only total, count and worst. Said out loud rather than guessed at,
  because a plausible histogram would have been believed.
* **`Script_PerfLab` is 27 ms in the resize capture and 3 865 ms in the mount
  capture.** In `resizeStorm` essentially all LuauUI work runs off the Heartbeat
  connection, not under the pass's script bar, so triaging that capture by "which
  script is hot" concludes LuauUI costs nothing and is wrong by 8 000 ms.
* **`mount.html` cannot rank LuauUI levers.** Its frames run 287–306 ms while the
  entire LuauUI phase inventory sums to 8.6 % of wall and roughly half the wall is
  inside no named scope at all. It answers "how slow is the ramp", not "which phase
  to fix". A scope that can see the ramp's own tree construction is owed.
* **Two zeros are health; nine are a missed window.** `resource` and `reset` at 0
  in `resize.html` is correct — `resizeStorm` lands no asset and tears nothing
  down. The failure mode to keep recognising is `perfPlace2gb.html`, where nine of
  twelve were zero.
* **`Relayouts` equals `Updates` exactly in `mount.html`** (92 = 92 on the rows,
  39 = 39 on the overlay panel): the engine batched nothing during the ramp. Open,
  unrelated to L-29.

---

## L-31 — a measure→publish cycle settles inside ONE flush (L-29 residual 1, paid — and re-priced)

**Date:** 2026-08-14 · **Commits:** `d7d0e42` (core), `404da2a` (renderer/presenter/spec),
`2c42cae` (lab + oracles), game `14327f3`
**Evidence tier: 1 — headless (Lune), a regression signal only.** No Studio and no
device number is claimed here. The instrument is an event COUNTER, not a clock
(see "the noise floor" below), so the counts are exact; the ms projection at the
end is labelled as a projection and is not a measurement.

L-30 named this the top lever at **−25 to −28 % of wall**. That estimate is
**too high, and this entry says so with the decomposition that replaces it.**
What was really available, and has been taken, is one of the two flushes and one
of the four solves — plus a correctness win that was not in the estimate at all.

### The noise floor, stated first

The whole-suite wall-clock floor is 2.69 % Σp50 / 4.99 % Σp95 and a single
scene's median spread is 27.4 %, so **no number below is a wall-clock number.**
Every figure is a count of `LuauUI/react`, `LuauUI/arrange` and `LuauUI/mount`
spans taken through `profile.setHooks`. **Same-arm spread over three consecutive
reps of both probes: ZERO — byte-identical output.** That is the property that
makes a 7 → 6 difference quotable at all; it would be meaningless as a timing.

### The shape, reproduced headless in the general form

`tools/lune/_probe_settle` builds the general case out of nothing but the public
API: a CONTENT surface laid out inside the safe area, and a DOCK surface whose
panel height is a `percent` of the viewport and which publishes its measured
height into `coreSafeInsets.bottom`. Three arms, same process:

| arm | react/step | arrange/step | content root rect on return → next frame |
|---|---:|---:|---|
| no round trip (control) | 1 | 2 | 655 → 655 |
| measure→publish | **2** | **4** | **655 → 551** |

**The round trip doubled both, and painted one frame carrying a number nothing
had settled** — the 104 px reservation arrived a frame late. That last column is
the finding L-30 did not have, and it is why the lab's overlay carries
`forgetReservation` at all.

`tools/lune/_probe_lab_settle` drives the REAL lab and reproduces the device
capture to three significant figures. Steady-state per `resizeStorm` step,
before: **3 react, 7 arrange, 2 mount** against the device's **3.03 / 7.12 /
2.00**. So the headless reproduction is faithful, and the device's 7.12 arranges
decompose by name:

```
flush A (env:batch)     content + overlay            2   the resize itself
refresh #1              content + overlay            2   structural dirt (lever 3)
flush B (onGeometry)    content + overlay            2   THE ROUND TRIP
refresh #2              content                      1   the data change
                                                     -
                                                     7
```

**Only 2 of the 7 are the round trip.** L-30 attributed ~4 by counting
"3 flushes × 2 surfaces", which double-counts the refresh-time solves — those
are the windowed list's legitimate structural re-solve, and they are lever 3's
territory, not this one's.

### The cause, in two facts

1. **The solve ran in the MIDDLE of propagation.** `geometryFacts`'s observer
   called `solveAndApply()` inline, so a surface committed to a layout before
   the flush had finished deciding what the environment was.
2. **The measurement was delivered a frame late.** `feedGeometry` ran from
   `presenter.refresh()` on the host's frame connection, so a consumer's derived
   write could never join the flush that caused it. It always opened a new one.

### The fix: a settle phase (`core:settle`)

Stated in `src/core/contract.luau`, which is the file the conformance suite
enforces:

> Settle callbacks run after propagation quiesces, in REGISTRATION order; a
> callback that writes ends the pass, propagation drains, and the pass RESTARTS
> from the first callback, so every settle callback observes every other one's
> publication. Passes repeat until one writes nothing.

**Convergence, not an open loop.** A settle pass counts against the existing
`FEEDBACK_ROUND_CAP`, so a cycle that will not settle is the same loud
quarantined error an effect feedback loop already was — never a hang, never a
silent frame. Glitch-freedom is untouched (settle is not an observer and
receives no value), observer creation order is untouched, and it runs INSIDE the
flush, so a top-level write still returns with all of its consequences applied.
`Counters` gains `settles` so an un-disposed registration is a leak the 24
registry-neutrality specs can see.

The renderer's geometry re-solve and the presenter's geometry feed both became
settle work (`controller.onSolved` is the new seam). Plus one narrowing that
falls out of it: **an `edgeToEdge` surface no longer depends on
`coreSafeInsets`/`deviceSafeInsets`** — it reads one and throws it away and
never reads the other — so every scrim, backdrop and dock stopped re-solving for
an inset it is defined to ignore, including for a reservation it published
itself.

### Measured, tier 1, exact counts

| | before | after |
|---|---:|---:|
| general shape — react/step | 2 | **1** |
| general shape — arrange/step | 4 | **3** |
| general shape — rect on return → next frame | 655 → 551 | **551 → 551** |
| real lab — react/step | 3 | **2** |
| real lab — arrange/step | 7 | **6** |
| real lab — mount/step | 2 | **1** |

The `mount` halving is a side effect worth recording: with the geometry settled
before the frame's `refresh()`, one of the two structural syncs L-27 recorded and
L-29 left untouched has nothing to do. **Lever 3 is half paid by accident.**

**Projected on the device, and labelled as a projection**: −1 arrange at
9.136 ms and −1 measure at 3.236 ms is 12.4 ms of a 173.2 ms step, and −1 mount
at 6.387 ms is another 6.4 ms — about **−11 % of wall**, not −25 to −28 %. A
device capture is owed before that number is quoted as measured.

### The honest result: settling in one flush does NOT halve the solves, and why

The round trip's two solve generations are set by the DATA DEPENDENCY, not by
the framework. The dock's height is only known after the dock solves; the
content surface must therefore solve once against the pre-publication
environment and once against the settled one. The only thing that would remove
the first is settling the PRODUCER before the CONSUMER — and settle callbacks run
in registration order, while z-order is present order, so a dock presented ON TOP
settles LAST, after the surface it publishes to.

**A "producers first" or "topmost first" settle order was considered and
refused.** The framework has no principled way to know that one surface produces
what another consumes, and an order learned from history would break the
contract's own reproducibility promise. What is left is the honest floor: one
solve per surface per generation of settled values, inside one flush, before
anything is committed.

`forgetReservation` in the lab's overlay therefore **stays**, and deleting it is
the mutation proof: two NAMED cases redden immediately (`a viewport change DROPS
the overlay's stale reservation before the workload re-solves` and `the full
resize pass leaves the workload MOUNTED`) with the 122 px content box and 17 px
overflow its own comment describes. What changed is its price: both writes now
land inside the flush that caused them.

### The lab's own bug, found by writing the general shape as a test

`reserveBottom` compared against a REMEMBERED reservation, and the memory was
wrong every time the adapter republished the fact — `roblox_env.pushViewport()`
is the author of `coreSafeInsets` and rewrites all four edges on every resize,
zeroing the reservation without the overlay hearing about it. The cache then said
"already reserved" and the republication never happened. It compares the LIVE
fact now.

### The instrument (director's standing instruction)

`resizeStorm` reports **`reactPerStep`** and **`arrangePerStep`**, off
`profile.counters()`, nil-safe under `cleanCapture`. `reactPerStep` is the
feedback-loop detector: a resize step drives exactly two writes, so anything
above two is a write made in RESPONSE to the resize. Both numbers had to be read
out of a binary MicroProfiler dump by hand to diagnose this; they are now a field
in the pass's own report.

### Traps worth keeping

* **A check on the lab's profiler readout, driven headlessly, reads ZEROS.**
  `host.profile` defaults to a no-op stub whose `byScope` is always empty, so a
  spec must hand in the REAL module (as the Studio lab client does) or it proves
  nothing. Caught by asserting the instrument is non-zero before asserting its
  value.
* **`edgeToEdge` has TWO independent authorities** — the renderer zeroes `insets`
  before the solve AND the solver takes the whole viewport as the content rect.
  Breaking either alone leaves the differential test GREEN. A mutation proof over
  a belt-and-braces invariant has to break every belt.
* **A memo cannot witness "did propagation run".** The first version of
  `settle-callbacks-never-see-a-half-propagated-graph` used a memo and passed
  with the drain removed, because a stale memo recomputes on `get`. Only an
  observer notification count can see it.
* **The lab's `coreSafeInsets` batching-oracle exclusion was NOT deleted**, which
  is what L-29 predicted would happen. The fact still legitimately moves twice
  per resize — that is what a measure→publish cycle IS — so the exclusion stands
  and the new `reactPerStep` ceiling is the check that pins what was fixed.

### Residuals

1. **The remaining generation.** One of the round trip's two solve generations is
   removable only by ordering producers before consumers. Worth ~1 arrange per
   geometry change per consuming surface; needs a principled rule, and there is
   not one yet. The elegant version is a separate publish/apply split (SwiftUI's
   PreferenceKey shape), which is a feature, not a patch.
2. **Two authors for one fact.** The whole intermediate generation exists because
   the platform adapter and the app both write `coreSafeInsets`. An additive
   reservation channel — the app declares a reservation, the framework composes it
   with the platform's insets — would remove the round trip entirely rather than
   making it cheap. Named, not built.
3. **A device capture is owed** before the −11 % projection above is quoted as a
   measurement, and to confirm the `mount` halving on the real engine.


## L-32 — the AFTER number, on the same engine that gave the BEFORE

**Date:** 2026-08-14 · **Evidence tier:** 2 (real Roblox engine, live `screen_target`
adapter painting real Instances)

L-29 measured the defect on this machine at tier 2 and the fix only headlessly.
The place has since been rebuilt and reopened with current source, so the same
probe was re-run against the shipped code — same engine, same 40-row tree, same
six-fact adapter group, same session-day.

| | pre-fix (this morning) | post-fix |
|---|---|---|
| batched six-fact resize, 360x691 | 4 | **1** |
| batched six-fact resize, 1200x800 | 5 | **1** |
| batched six-fact resize, 390x844 | 5 | **1** |
| 3x republish of IDENTICAL numbers | 3 | **0** |

The republish row is the one that only exists because of the value-comparison
correction the RED-TEAM forced (`897c9df`): the adapter rebuilds those tables on
every push, so before that change a `TopbarInset` change alone re-solved the whole
surface for a viewport that had not moved.

**Method note, because it is the reusable part.** The Play bridge was wedged, so
this ran in the **Edit** datamodel with the surface parented to an explicit
`CoreGui` folder and destroyed on the way out (verified absent in the same call).
Edit lacks a PlayerGui, not an engine — the adapter paints real Instances either
way, and the counts are the adapter's own. Before running it, the Edit datamodel
was checked for a marker committed minutes earlier (`core:settle` present,
`custom.luau` 21,032 chars matching disk) so the numbers are a claim about
today's code rather than about the built place. `renderer.luau` read 238,180
against 242,954 on disk — stale, exactly as the >=200,000 write cap predicts, and
a reminder that the three remaining over-cap modules cannot be measured this way.

---

## L-33 — the lab learns to see round 3's collection work, and what it costs

**Date:** 2026-08-14 · **Evidence tier: 2 — Studio, the real Roblox engine**
(live `screen_target` adapter painting real Instances, Play session, the lab's own
bootstrap). No device claim is made anywhere in this entry; the device note at the
bottom is what turns any of it into tier 3.

Round 3 shipped two things this lab could not see. Every workload above this entry
windows by ONE number (`index x pitch`) and not one of them touches `newTable` at
all, so **`src/virtual_extents.luau` and `newTable{ virtualized = true }` shipped
with no perf row.** Two new workloads close that, and both mount their own surfaces
— so no existing number moved and nothing was re-based.

**`SCENARIO_VERSION` deliberately does NOT move**, and neither do `dataset.VERSION`
or `rows.VERSION`. The rule is "bump when a workload's STEPS change", and adding a
workload changes no other workload's steps. Bumping it was tried:
`tools/check_perf_captures.py` immediately declared all six admissible PL-9 rows to
"describe a workload that no longer exists", which would have discarded real
measurements of unchanged work in order to record an addition. The check was right
and the bump was wrong. A capture row already carries its workload id, so nothing is
ambiguous.

### `variable-extents` — four arms, and the middle one is the point

| arm | `itemExtent` | what it isolates |
|---|---|---|
| A uniform | a number | the pre-feature arithmetic |
| A' uniform | a number | **the same arm again — the control band** |
| B variable, FLAT | a function returning the SAME px | the prefix-sum machinery with the feature's benefit subtracted out |
| C variable, RAGGED | 1..4 text lines per row | the feature |

Every arm asserts `dump().itemExtentMode` before it measures. `itemExtent` accepts
a number, a `Readable` AND a function and only the third switches arithmetic, so an
A/B whose four arms silently ran one code path is exactly one typo away.

**The control, before any delta** — 2 000 rows, 40 edits, 60 scroll frames, flat:

| | A | A' | **spread** |
|---|---:|---:|---:|
| scroll step p50 | 0.2878 ms | 0.2850 ms | **0.0028 ms (1.0 %)** |
| grow-edit p50 | 3.589 ms | 3.653 ms | **0.0640 ms (1.8 %)** |

**The first cut of this pass hard-coded n = 8 and its grow-edit control band was
0.49 ms against a ~2.5 ms number — 20 %, larger than the effect being looked for.**
Raising n to 40 cut the band 7.7x. Both new passes therefore take `frames/reps`,
because an operator who cannot raise n cannot get out of that hole and a device is
noisier than a desktop, not quieter.

**The result:**

| | A/A' mean | B variable-FLAT | delta | vs band |
|---|---:|---:|---:|---:|
| scroll step p50 | 0.2864 ms | 0.2800 ms | −0.0064 ms | 2.3x — no cost |
| same-count edit p50 | 3.043 ms | 3.212 ms | **+0.169 ms (+5.5 %)** | 2.6x |
| grow edit p50 | 3.621 ms | 3.738 ms | **+0.117 ms (+3.2 %)** | 1.8x |
| **arranges per grow edit** | **1.00** | **1.00** | **0** | — |

**The running-offset index costs nothing measurable on a scroll frame, ~0.12 ms to
BUILD over 2 000 rows, ~0.17 ms to WALK on an edit that rebuilds nothing, and it
adds ZERO extra solves.** The two edit numbers are the two halves the pass separates
on purpose: `sameCountEditMs` leaves every extent where it was, so the index cache
hits and only the O(N) extent walk runs; `growEditMs` appends a row, which misses
the cache by construction and is therefore walk + prefix-sum build.

Arm C is reported but is **not** a like-for-like: ragged rows are taller, so it
windows 19 rows against 33 and spans 104 040 px of canvas against 48 960. Its
cheaper scroll step (0.218 ms) is less work, not faster work, and the entry says so
rather than banking it.

### `table-unified` — virtualization + multi-selection + reordering in one container

2 000 rows, three columns, headerless, `selection = "multi"`, `reorderable = true`,
25 rows in the tree. **Hosted row actions are absent and that is a verified refusal,
not an omission:** `newTable` rejects `virtualized` beside `rowActions` at
construction (v1) because Table WRAPS each actionable row, which is the one thing a
windowed canvas cannot host. "Virtualization + reordering + selection + hosted row
actions at once" is not a workload that can be built today.

**The control, before any delta** (A/B/A over `recycle`, three consecutive runs,
24 reps each):

| | ON #1 | ON #2 | **spread** |
|---|---:|---:|---:|
| `revealRow` p50 | 10.838 ms | 10.786 ms | **0.052 ms (0.5 %)** |
| `moveRow` p50 | 5.560 ms | 5.905 ms | 0.345 ms (6.0 %) |
| range-select p50 | 0.755 ms | 0.801 ms | 0.046 ms (5.9 %) |
| scroll step p50 | 0.450 ms | 0.508 ms | 0.058 ms (12.1 %) |

**What the container costs** (recycle ON, the shipped default):

| verb | p50 | p95 | arranges/rep |
|---|---:|---:|---:|
| scroll step (steady, 40 px/frame) | 0.450 ms | — | — |
| **`select` × 2, a 201-row range spanning ~180 unmounted rows** | **0.755 ms** | 1.66 ms | **0.00** |
| `moveRow` on a row no window holds | 5.560 ms | 10.7 ms | 1.17 |
| **`revealRow` on a row no window holds** | **10.838 ms** | 13.9 ms | 1.25 |

**A 201-row range selection across the window costs 0.76 ms and provokes ZERO
solves.** That is the unified container's central claim measured rather than
asserted: selection is MODEL state and only the mounting is windowed.

### The top cost is a seek, and it is NOT a framework defect — the Table beats the list at it

`revealRow` at 10.8 ms is 24x a scroll frame, so it was the obvious suspect. It is
a **full window replacement**: revealing row 120 from row 1500 unmounts 25 rows and
mounts 25 more, which is L-3's seek-versus-steady distinction one control over.

The comparison that settles it, same session, same 2 000 rows, same engine:

| | mounted rows | worst step (frame wait excluded) |
|---|---:|---:|
| `newVirtualList` `scrollSeek` (dense-scroll) | 14 | **23.66 ms** |
| `newTable{ virtualized }` `revealRow` | **25** | **13.10 ms** |

**The virtualized Table replaces a LARGER window, with three columns per row, for
about half the worst-case cost of the list's equivalent seek.** There is no
disproportion to fix here.

### Where the frame actually goes — MicroProfiler, via LibMP

Taken programmatically (`LibMP.Control:CaptureToBufferSync` → `Session.OpenFromBuffer`
→ log iterator with frame-local attribution), 127 frames of one `tableUnified` pass,
2 333 ms of wall. Shares are of summed per-frame CPU tick span; scopes on several
threads sum above 100 %, so read the RANK, not the total.

| scope | % frame | n | ticks/occ |
|---|---:|---:|---:|
| `LuauUI/present` (inclusive) | 24.04 % | 254 | 48 073 |
| **`LuauUI/mount`** (structuralSync) | **8.47 %** | 45 | **95 566** |
| `$newindex` (engine property writes) | **6.74 %** | **79 538** | 43 |
| `LuauUI/arrange` | 5.99 % | 70 | 43 478 |
| `LuauUI/react` | 3.92 % | 168 | 11 844 |
| `LuauUI/measure` | 2.05 % | 70 | 14 855 |
| `LuauUI/commit` | 1.89 % | 140 | 6 861 |
| `LuauUI/focusmap` | 1.04 % | 508 | **1 041** |

`Sleep` at 1 138 % across threads says this session is nowhere near CPU-bound, so
these are shares of a frame with room in it.

Two things to keep:

* **`LuauUI/mount` is the largest LuauUI scope by far per occurrence — 2.2x an
  `arrange`** — which is the same ranking the lab's own `profile.setHooks`
  instrument produced independently (4.57 ms/mount against 1.63 ms/arrange, from a
  reps=1 vs reps=41 differential over the same pass). Two instruments, one answer.
* **`$newindex` is 79 538 property writes in 127 frames — 626 per frame — and it
  costs MORE of the frame than `arrange` does.** The framework's own phase scopes
  cannot see one byte of that; it is exactly the blind spot LibMP was worth
  reaching for.
* `focusmap` at 1 041 ticks/occurrence and 1.04 % of frame: L-27's `structureEpoch`
  cache still holds on a container that restructures constantly.

### Instance recycling eliminates 24 % of creates on this container and buys 1.7 %

Measured directly, with the MECHANISM rather than a black-box A/B — `tableUnified`
now reports `controller.stats()`'s park/refuse/recycle counters, because a selector
whose effect is invisible is a selector nobody can trust.

| | recycle ON | recycle OFF |
|---|---:|---:|
| `creates` | **5 173** | 6 821 |
| `recycled` (creates served from the pool) | **1 648 (24 %)** | 0 |
| `parked` / `parkRefused` | 1 712 / **2 575 (60 % refused)** | 0 / 0 |
| `revealRow` p50 | 10.786–10.838 ms | 11.011 ms |
| `moveRow` p50 | 5.560–5.905 ms | 5.681 ms (**inside the band**) |
| scroll step p50 | 0.450–0.508 ms | 0.485 ms (**inside the band**) |

**Recycling removes a QUARTER of all Instance creates and moves the reveal by
1.7 %.** Only `revealRow` clears its 0.5 % control band at all; `moveRow`, the range
select and the scroll step all sit inside theirs.

That is the useful, quotable finding, and it is a caution as much as a result:
**Instance materialisation is not the lever for a windowed Table.** L-9-through-L-28
established creation as the dominant cost on a flat `newVirtualList` (recycling is
worth −32 % there); on a three-column windowed Table it is worth under 2 %, and the
frame has moved to the solve and to the 626 property writes `$newindex` counts.
**60 % of park attempts are refused** — a named, mechanism-level lever if anyone
wants to raise the 24 %, but on this measurement it would be chasing under 2 %.

### Traps and method notes worth keeping

* **`lune run tools/lune/studio_sync` has a `perf` argument and the default is the
  GALLERY tree.** Running the default and injecting it into the performance place
  overwrote `ReplicatedStorage.LuauUIScenarios` with the gallery registry and added
  a second `StarterPlayerScripts` bootstrap, so Play booted the SHOWCASE. The
  symptom was `LuauUI_PerfLabReady = nil` and a console line reading
  `[LuauUI Gallery]`. Both trees mount at the same path, which the tool's own header
  says; the injector cannot detect the mix-up because every write it makes succeeds.
  **Check the console banner names the place you think you are in** before trusting
  any number out of it.
* **A second sync server cannot share the port.** `PORT` is a constant, so a perf
  inject while a gallery server is already serving 8642 needs a copy with a
  different port rather than killing the running one out from under whoever started
  it.
* **`FetchTimerDesc(...).TimerName`, not `.Name`** — the skill's example says `Name`
  and the field does not exist, so every scope in the first capture read as `idN`.
* **LibMP timestamps are raw ticks with no published frequency.** `FetchGeneralInfo`
  carries none and `FetchUtcTimestampSamples` returned a single sample. Calibrating
  against wall time is unreliable because the 256-frame ring holds frames older than
  the window being timed. **Report shares of summed frame span, which are exact and
  unit-free, and take absolute ms from the pass's own clock.**
* **The active Studio instance can be re-elected under you.** Mid-session the MCP
  switched to `LuauUI-Showcase.rbxl`; the giveaway was a `Client datamodel is not
  available in Edit mode` error followed by another agent's console output.
  `set_active_studio` before any measurement, not once at the start.
* **Probe hygiene, verified in the same call:** after both passes,
  `mountedRows = 0`, PlayerGui holds only `LuauUI_PerfLabOverlay`, `guiObjects = 42`
  in one ScreenGui, and the core reports 5 scopes / 36 signals / 28 memos after
  seven pass runs. Both passes tear down inside `pcall` + `finish()` so the error
  path drops the surface too.

### Taking this to a device

`docs/handoff/2026-08-14-device-capture-collections.md`.

### Residuals

1. **`parkRefused` at 60 %** on a windowed Table. Raising the 24 % recycle rate is a
   real lever on Instance creates and, on this measurement, worth under 2 % of the
   verb. Named, not built.
2. **`$newindex` at 626 property writes per frame** is now larger than `arrange` in
   the capture and is invisible to every framework scope. Nothing here says how many
   of those writes are redundant — the property diff (L-18) exists and its coverage
   on this path has not been measured. That is the next honest question.
3. **A device capture is owed** before any number in this entry is quoted as a device
   claim, and specifically before the −32 %-versus-1.7 % recycling contrast is
   generalised: a handset's Instance-creation cost relative to its solve cost is not
   this laptop's.

---

## L-34 — the OTHER half of the round trip: a publication that is a PROP

**Date:** 2026-08-15. **Files:** `src/render/renderer.luau`, `src/mount.luau`,
`src/present/presenter.luau`. **Follows:** L-31 (which closed the same cycle for
a publication that is an *environment* write) and
`docs/lessons/the-node-that-must-spend-it-lives-outside.md`, which flagged this
one rather than smuggling it into a bug fix.

### The shape

A consumer measures this surface's geometry from `onGeometry` / a contribution's
`syncGeometry` and publishes a number derived from it. L-31 made that write join
the flush that produced the rects — but only the *environment* half converged in
that flush, because `geometryFacts` is a memo over env signals and the renderer's
settle callback re-solves on it.

A publication that lands in one of the surface's **own node props** took a
different road. `mount.luau` binds a reactive prop through `core:observe`, which
writes `node.props` and pushes a dirty entry, and that queue is drained by
`controller.refresh()` — the host's **next frame**. So the solve that produced the
measurement laid the tree out against the old prop.

Shipped instance: a Table's header pays the scrollbar gutter its body spent, and
`present`'s own solve paid it late. **One frame**, already down from two.

### The fix

`feedbackMark` is the mounted tree's dirty sequence as the solved-listener
notification *begins* (`root.dirtySeq()`, new — monotonic, so it survives a
`takeDirty` between mark and check). Everything past that mark is, by definition,
something a listener published. Two arrival times, one rule:

* solve from `refresh`/`initialRender` (no flush open) — the listener's `:set`
  flushes synchronously, so the dirt is on the tree when the notify loop returns
  and the re-solve happens inline;
* solve from the renderer's settle callback (a flush **is** open) — the write joins
  `writeSet`, the core ends the pass, drains propagation and **restarts from the
  first callback**; `feedbackArmed` carries the mark across that one pass boundary,
  and the feedback branch is placed first in the callback for exactly that reason.

The presenter's very first `feedGeometry` happens outside any solve (`initialRender`
runs before contributions are discovered), so it asks for the same drain by hand
through `controller.settleFeedback()`, with the `onSolved` listener now registered
*before* it so a two-step publication converges there too.

### Termination

`SOLVE_FEEDBACK_ROUND_CAP = 8`, mirroring the core's `FEEDBACK_ROUND_CAP`: a
publication derived from the rect it moves produces a new number every solve, and
that is a loud error — quarantined into `lastError` when it fires from the settle
phase, propagated from `refresh` exactly as a throwing `solvedListener` already is.
Named case: *"a prop round trip that will not converge is a LOUD error, not a hang"*.

Nothing about glitch-freedom or observer creation order moves: the drain publishes
nothing, touches no observer, and runs inside the solve it belongs to. No new core
guarantee was needed — the two properties it stands on (a settle pass restarts from
the first callback after any write; the write is drained before it does) are already
stated in `src/core/contract.luau`.

### The numbers — exact counters, not timings

Deterministic counters from the new fixtures, so there is no A/A question to answer:
nothing here is a wall-clock measurement, and no timing claim is made.

| | before | after |
|---|---:|---:|
| frames before a Table's header grid equals its body's, from `present` | 1 | **0** |
| `stats.feedbackSolves` on the frame a consumer publishes a layout prop | n/a | **1** |
| `stats.feedbackSolves` for the identical scene with the publication removed | n/a | **0** |
| L-31's own resize scene, solves per step (control / round trip) | 2 / 3 | 2 / 3 (unchanged) |

**The cost, stated:** one extra solve on the frame a consumer publishes — which is
the solve the *next* frame used to pay. The drain deliberately does **not** consume
the dirty queue, so `refresh` still commits the paint half and `onAppear`/
`onDisappear` ordering and the structural sync stay byte-identical; this closes the
layout frame, not the property-write cadence.

### One behavioural consequence, found by the suite

`row_actions`' post-commit paint restore is deferred to "the next `syncGeometry`",
and that sync's write now lands in the solve that announced it rather than the one
after. C8a's actual guarantee is untouched — an owner that removes the row inside
`onAction` disposes it before that sync runs — but a *phantom* row (an owner that
does not remove it) comes back one frame sooner. `tests/table.spec.luau`'s
"committed delete" case had been reading the row's height at the end of the tick
that fired; it now reads it **at the fire**, from inside `onAction`, which is where
the invariant actually lives and is strictly stronger than the sample it replaces.
Measured at the fire: 0.000064px (the spring's numeric settle epsilon) against ~40px
for an early fire.

### Residual

`dirtyContains = nil` before the feedback re-solve is a **conservative guard with no
biting case**: it enforces the rule `controller.refresh` already states in its own
comment ("a re-entrant solve must not reuse it, and gets a full solve instead"),
because the incremental set is closed over the dirt the refresh took and the node a
listener publishes into is by construction absent from it. Several fixture shapes
were built to make removing it redden a case — sibling subtrees, a fixed outer band
holding a moving inner probe — and `arrange`'s skip declined to fire on any of them
(it also requires the subtree to land on the rect it already had). It is kept
because a feedback solve is rare and a full solve is always correct; the honest
status is *unproven guard*, not *mutation-proven check*.

---

## L-35 — the collections round, on the device: two captures are evidence, one is a lab defect, and `arrange` is the answer again

**Date:** 2026-08-15 · **Evidence tier: 3 — physical device** (Samsung SM-A102U1,
Android 11, client 734), and therefore authoritative over every tier-1 and tier-2
number in L-33 and in `artifacts/variable-item-extents/perf.md`.
**Captures:** `variableExtent.html`, `tableUnified.html`, `asyncImage.html`,
`collectionChurn.html`.
**Full analysis, method, per-scope tables and per-frame histograms:**
`artifacts/performance-stress-places/device-capture-2026-08-15.md`.

### The usability verdict, first, because two of the four are not evidence

| capture | verdict |
|---|---|
| `collectionChurn.html` | **evidence** — and the most informative of the four |
| `variableExtent.html` | **evidence**, sampling one *unidentifiable* arm's edit phase |
| `tableUnified.html` | **half-evidence**: the workload demonstrably ran; the aggregate window is **0 frames**, so no timing survives |
| `asyncImage.html` | **not evidence — a lab defect**, twenty-nine byte-identical frames |

The director's report that the last two "didn't do anything visually" was right
about both and for two entirely different reasons, and only one of them is a bug.

### Decode corrections that invalidate a past technique

* **The event log's `u16` token is the timer record's `id`, NOT its array index.**
  `id != index` for every record in these blobs. Reading the log by index
  attributes every `LuauUI/*` scope to its neighbour: `arrange` and `measure` read
  **zero** tokens while `mount` read 120. Any past event-log claim taken by index
  is unsound.
* **The event log is three parallel equal-length columns** — `u8` at `0x80..0x84`,
  `u64` timestamps at `0x88..0x8c`, `u16` tokens at `0x90..0x94`. Enter/leave
  pairing across the flat array still does not work (L-30's finding stands: Lua
  scope *durations* are unrecoverable), but **occurrence counts are exact**, and
  `queuePresent` (exactly 1/frame, 30 in every ring) delimits frames. That yields
  a **per-frame histogram**, which is the instrument that found both defects below.
* **Check `header[0x20]` before reading a timer table.** `tableUnified.html`
  carries a full event ring and an entirely empty aggregate. A legitimate capture
  reads as twelve zeros and gets filed as a broken workload.
* **`collectionChurn`'s ring and aggregate disagree about rates by 4.6×** (26.0 vs
  5.72 arranges/frame): different windows. Per-occurrence costs are unaffected;
  per-frame rates must come from the ring. Never multiply an aggregate rate by a
  ring frame period.

### `async-image-churn` was profiling a pass that does nothing — the THIRD aiming failure

`asyncImage.html` is twenty-nine consecutive frames of **2 arranges, 2 measures,
0 mounts, 0 `LuauUI/resource`, 0 `LuauUI/reset`**, with no `Context=` engine layout
counter emitted at all. `profileWindow` loops `w.passes[1]`, and this workload's is
`imagesCold`, whose whole body is `settings.resourceState = "cold"` plus one
`refresh()`. Looped, it re-sets a flag that is already set. Priced headless per lap
(`tools/lune/_probe_profile_aim`):

| pass | arrange | mount | resource |
|---|---:|---:|---:|
| `imagesCold` / `imagesWarm` | 1 | **0** | **0** |
| `imagesFail` | 1 | **0** | 2 |
| **`imagesReuse`** | **9** | **8** | 0 |

Two guards already exist for the first two aiming failures (a workload with no
framework in it; a window that cannot escape pass #1). This is a new class: a pass
that is legitimate inside its declared *sequence* and inert on a *loop*.

**Fixed, two ways, neither touching any workload's `passes` list** — so
`SCENARIO_VERSION` does not move and `check_perf_captures.py` stays PASS at 18
admissible rows (L-33's ruling on additive change, applied again):

1. **`profilePass`** on the workload declaration — `async-image-churn` →
   `"imagesReuse"`. An explicitly named pass still wins.
2. **`lapWork`** — the scope deltas of the last lap, returned by `profileWindow`
   and written to the overlay status line every lap
   (`arrange=9 mount=8 react=11 resource=0`). A lap reading `arrange=1 mount=0` is
   now visible **on the phone before the dump is taken**. A readout, not a refusal:
   `idle-baseline` is a legitimate zero and a threshold would be a number invented
   rather than measured. `lapWork.measured` is the honesty field, because
   `cleanCapture` turns scopes off and a bare zero would accuse a healthy pass.

**Mutation-proved, one at a time** (four new cases in `tests/perf_lab.spec.luau`):
deleting `profilePass` reddens only *"loops the workload's declared PROFILE pass"*;
`work.measured = true` reddens only *"says the readout is UNMEASURED"*; a lap delta
of `after - after` reddens only *"reports what ONE lap provoked"*.

### `collection-churn` earns its keep: the mounting is right and the solving is not

Per-frame histogram, **29 of 29 frames identical**: `26 arrange · 26 measure ·
26 react · 0 mount · 52 commit · 26 present`. `passes.insert` runs 25 iterations
with **no yield inside the loop**, so one lap is one frame; 25 + 1 = 26, and the
headless probe returns the same 26/26/52/0-mount. Composed with the aggregate's
per-occurrence costs, **26 × 9.384 ms = 244 ms of `arrange` inside a 557 ms
frame — ~44 % of the frame in one scope.**

* **`LuauUI/mount` = 0 across all 29 frames.** Twenty-five inserts at logical row
  ~500 of 2 000, window at the top, provoke **not one structural sync**. The
  workload's own question — *"do updates stay proportional to changed and visible
  content?"* — is answered **yes for materialisation**, on hardware, at 2 000 rows.
* **Every one of those inserts still costs a FULL solve.** An edit that changes
  nothing any mounted row displays re-derives every rect.
* **`arrange`'s worst single occurrence is 298.87 ms** — 54 % of an already
  catastrophic frame in one call, and 2.3× L-30's resize tail (131.23 ms). Largest
  single-occurrence figure ever recorded in this lab.
* "Nothing happened visually" is explained twice over: the insertion point is ~475
  rows below the last mounted row, and at 1.8 fps a repaint would read as frozen
  anyway.

**The missing yield is a real defect and is deliberately NOT fixed.** The diff is
designed (time each rep between `clock()` calls, `telemetry.step()` outside the
timed region, report `summarize` + `arrangesPerRep` — the pattern `extentArms` and
`tableUnified.verb` already use), but it changes the workload's STEPS, which by
this log's own rule requires bumping `SCENARIO_VERSION` and thereby declares all
18 admissible Studio capture rows to describe a workload that no longer exists.
L-33 faced this exact trade and refused the bump; the same answer holds. Named as
a residual with the diff ready.

### `variable-extents`: L-33's zero-extra-solve claim holds at tier 3; the +96 % does not become a device claim

The ring's histogram identifies the phase unambiguously — 23 frames of `1 arrange,
0 mount` (`sameCountEdit`, no row count change, nothing remounts) then 6 of
`1 arrange, 1 mount` (`growEdit`, canvas and window change). The 23 / 6 split
matches the pass's 24 / 24 structure.

> **Arrange is exactly 1.00 per data edit across 29 consecutive frames**, in both
> the cache-hitting and the cache-missing case, and it stays 1.00 while a
> structural sync is also happening. L-33 recorded `arrangesPerGrow = 1.00` at tier
> 1; it now holds at tier 3.

**The +96 % scroll-step cost of `itemExtent = "measured"` cannot be confirmed or
refuted by any device dump, and this is an instrument mismatch rather than a
missing measurement.** One `extentArms` lap is five arms × (24 + 24 + 60) = **540
frames**; the aggregate window is 60 and the ring is 30. The window lands inside
one arm and **nothing in the dump names which arm** — every arm mounts the same
surface id, the same canvas path, and indistinguishable engine layout counters.
The arm-level p50s and the `harnessSpread*` control bands the whole comparison
rests on **are computed every lap** and are returned to the caller; they are simply
not in the binary dump, and the person holding the phone cannot read them.

So `artifacts/variable-item-extents/perf.md`'s **+96 % converging / +27–40 % steady
state, against a 1.6 % A/A control**, remains **tier 1** — a good number, honestly
labelled, and the justification for `"measured"` being opt-in is unchanged and
unchallenged. What is owed is not a re-measurement but a *route*: the pass's own
headline p50s surfaced where a device can show them. `lapWork` is the seam;
building it out is a lab feature, not a patch. **Named, not built.**

### `table-unified`: the workload ran, and nothing timed it

`tableUnified.html` carries the surface (`Cause=LuauUI_TableUnified Root=…
Relayouts=6 Updates=57 Resizes=71`), a 30-frame ring at 99.95 ms/frame, and an
aggregate window of **0 frames** with every timer at zero. Its ring landed in a
uniform stretch (`2 arrange · 2 measure · 1 mount · 3 commit · 2 present` on 26 of
29 frames), not on `selectRange`'s 12 reps.

**The 201-row range selection provoking 0 arranges is therefore still a tier-2
Studio claim**, unmoved and unchallenged. The handoff's named invariant
(`selectRange` reports `arrangesPerRep` of 0) is not owed an explanation by
anything in this capture; it is simply not tested by it. Same for recycling's 24 %
of creates for a 1.7 % reveal cost against a 0.5 % band — the recycle A/B needs two
dumps and neither carries timings.

### `$newindex` (L-33 residual 2): the device instrument does not contain the cost

`$newindex` and `$index` appear as **registered timers with count 0 in all four
blobs**, and no `$`-prefixed timer has a non-zero count in any of them. Roblox
retail client dumps do not populate Luau function-level scopes; L-33's 79 538
writes over 127 frames came from **LibMP inside Studio**. Nothing here says that
finding is wrong — only that **a device capture cannot see it**, so
"is `$newindex` still the top lever?" cannot be answered this way and residual 2
stays open as a Studio + LibMP question.

### The lever, and why nothing was optimised

`LuauUI/arrange` is the top cost in **all four** captures:

| capture | ms/occ | occ/frame | share | worst |
|---|---:|---:|---:|---:|
| `collectionChurn` | **9.384** | 26.0 | **~44 %** | **298.87 ms** |
| `variableExtent` | **10.569** | 1.02 | 28.3 % | 22.60 ms |
| `asyncImage` (inert) | 5.269 | 1.77 | 19.6 % | 29.95 ms |
| `resize.html` (L-30) | 9.136 | 7.12 | 37.5 % | 131.23 ms |

**9.1–10.6 ms per occurrence across four independent workloads and two capture
sessions**, 2–3× `measure` per occurrence everywhere — a stable number that does
not depend on what provoked the solve, and confirmation that the cost is rect
derivation rather than text metrics.

**Not touched, as a routing decision:** `arrange()` is `src/layout/solver.luau`,
which another agent is editing concurrently. The 298.87 ms tail is new and is the
thing to hand that agent or to schedule after them.

**The second lever this capture opens**, and it is genuinely new: L-27 measured
incremental layout as inert on a *resize* (2 partial solves of 65 — a resize
changes every constraint). **A collection edit is the opposite case** — one row's
data moved and the viewport did not — and no capture in this log has ever measured
incremental layout on it. `collection-churn` now prices exactly that shape at 26
full solves per frame with zero structural change. Same file, same agent, next
question.

Recorded as healthy for the third session running: **`focusmap` at 0.125 ms/occ
(`variableExtent`) and 0.047 ms/occ over 772 occurrences (`collectionChurn`)** —
L-27's `structureEpoch` cache holding on a container that restructures constantly.
And for the fourth session running, **nothing is GPU-bound**: 33.97 ms
`RenderTotalTime` against a 557 ms frame.

### Residuals

1. **`insert`/`remove`/`reorder` run a lap in one frame.** Diff designed, refused
   on the `SCENARIO_VERSION` trade above.
2. **A 60-frame window cannot aim at a 540-frame pass.** `extentArms` and
   `tableUnified` both compute their headline numbers out of a dump's reach.
   Surfacing a pass's own p50s through the status line would make a device capture
   of the measured-extent question possible for the first time.
3. **`table-unified` is owed a re-capture** with the aggregate armed, and
   specifically one that lands on `selectRange`.
4. **`LuauUI/scenario`'s worst occurrence is 52.55 ms** in `collectionChurn`
   against 0.010–0.019 ms elsewhere — the instrument absorbing one bad frame.
   Not investigated; recorded before it is quoted as workload time.

---

## L-36 — the two levers get workloads, and the ranking changes: it is DEPTH, and the lab has been measuring the wrong configuration

**Date:** 2026-08-16 · **Evidence tier: 1 (headless Lune) + 2 (Studio, real
engine Luau VM).** No device claim is made here; the handoff
`docs/handoff/2026-08-16-device-capture-arrange-and-edits.md` is what asks for
one.

L-35 §7 ranked two levers and recorded that **neither had a workload aimed at
it**. `arrange` was the top cost in all four device captures (9.1–10.6 ms/occ,
worst 298.87 ms) and nothing could be done about it because no analysis could get
*inside* one scope wrapping one recursive walk. Incremental layout had been
measured inert on a *resize* (L-27) and never on a *collection edit*, which is
the opposite case. This entry is those two workloads and what they immediately
found.

### The instrument, and the four rules it obeys

`arrange-shapes` (nine arms) and `edit-locality` (five arms) live in
**`examples/performance/lab/levers.luau`** — its own module because `perf_lab` is
172 876 characters against the 200 000-character `Source`-WRITE cap, and a module
that crosses it stops live-syncing into an open Studio session *silently*
(`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`). Spending three
quarters of the remaining headroom on the one file a profiling session has to be
able to live-patch is how a future session manufactures false evidence.

Each of the four rules below closes a capture this lab has actually lost:

1. **An arm IS a pass.** One lap = one arm = ~24 frames, so a 60-frame
   MicroProfiler aggregate contains it whole. `extentArms` is 5 arms × 108 = 540
   frames per lap, which is why `variableExtent.html` could not answer the
   question it was built for.
2. **The arm identity is a `workspace` attribute**, for free:
   `profileWindow` already stamps `LuauUI_ProfilingPass`, and an arm is a pass.
3. **Every rep yields**, `telemetry.step()` outside the timed region.
4. **`lapWork` is populated honestly** — the phone reads `arrange=24 mount=0`
   before a dump is spent.

And one new control, because an arm comparison needs one dump per arm and the
operator is holding a phone: **`Arm >`** in the overlay's action row moves a
per-workload pointer and says where it landed; `Profile 1` reads it. Two buttons
rather than one, because `Profile 1` runs until Stop and a control that both
advanced the arm and started a run would race the loop it had just started.

**`SCENARIO_VERSION` does not move.** No existing workload's steps changed, so
`tools/check_perf_captures.py` stays PASS at 18 admissible rows. Same ruling as
2026-08-14 and L-33.

### Did arrange get finer profile scopes? NO, and the reason is structural

`profile.MAX_SCOPES` stays **12**. This was judged, not ducked:

`arrange` (solver.luau:2448-3809) is **one recursive per-node function with a
`node.kind` dispatch chain**. It has no prologue, no epilogue, no per-solve phase
structure at all — the stack fill distribution, the shrink pass and its
re-measure, the wrap line-breaking, the grid track consumption and the scroll
canvas extent are each the *body of one invocation*, running once per node of
that kind. **There is nothing inside arrange that a scope could wrap once per
solve.** A `profile.span` on any of them opens a scope per node — a closure and
two pcalls per node per frame — which is precisely the per-call-site label set
`src/core/profile.luau` rule 1 forbids, and would cost more than it measures.

But the same fact hands the measurement over for free: **arrange's phases are
dispatched by node kind, so a tree built of ONE kind isolates that kind's
phase.** That is what the nine arms are. It needed no new scopes and no edit to
`src/layout/solver.luau`, which another agent is live in.

**If a future mission wants per-phase numbers inside arrange, the right
instrument is not a scope — it is a counter on `ctx` beside the existing
`ctx.arranged` / `ctx.measured` / `ctx.skipped`, surfaced through `result.work`
and `controller.stats()`.** That is the pattern this codebase already uses, it is
free when nobody reads it, and it is a solver edit — so it is routed, not taken.

### Lever 1, priced — and the answer is not the one the arms were designed around

Tier 2, Studio, warmed then **ABBA-interleaved** (a straight forward sweep put
the A/A control at **35 %** because the first arm pays the solver's first-call
cost; interleaving brought it to 2.3 %). n = 120. Every arm is 240 leaves; only
the tree differs.

**A/A control first: `flat` 1.196 vs `flatRepeat` 1.224 µs per arranged node =
2.3 %. Nothing below that is a result.**

| arm | µs/arranged node | vs `flat` | measures per arranged node |
|---|---:|---:|---:|
| `flat` (control) | 1.196 | — | 2.00 |
| `flatRepeat` (A/A) | 1.224 | +2.3 % | 2.00 |
| `zstack` | 1.295 | +8.3 % | 2.99 |
| `wrap` | 1.288 | +7.7 % | 2.00 |
| `scroll` | 1.811 | **+51 %** | 1.99 |
| `fill` | 3.014 | **+152 %** | 2.99 |
| `deep` | 10.355 | **+766 %** | **16.39** |
| `deepScroll` | 14.971 | **+1152 %** | 16.33 |

**The lever is DEPTH, and the mechanism is re-measuring, not placing.** The same
240 leaves cost **8.7× more per node** under 30 nested stacks than under one, and
the last column says why: a flat tree measures each node twice per solve, a
30-deep tree measures it **sixteen** times. Every enclosing level re-measures the
subtree below it (arrange calls `measure` from a dozen sites — scroll's
`measureAll`, the stack's base/hug/post-shrink/post-fill passes, zstack's
diagnostic *and* real measure).

`fill` (+152 %) is second and real — the largest-remainder `table.sort` plus the
fill second measure, visible as exactly +1 measure per leaf. `zstack` and `wrap`
are inside or barely outside the band.

### The refuted hypothesis, kept because it is the finding

`solver.measure`'s memo opens `if not ctx.hasScroll then return
measureUncached(...) end` — the cache only arms itself when the tree contains a
ScrollView. `deepScroll` is the single-variable test: the same 240 leaves, the
same 30 levels, the same provocation, inside a scroller.

**It does not help. `work.measured` (which counts UNCACHED measures) reads 4 425
for `deep` and 4 426 for `deepScroll` — the cache produces ZERO hits** — and the
scroller's own double `measureAll` makes the arm 45 % slower. So the `hasScroll`
gate is not the thing to open.

The candidate mechanism, from source and **not yet measured**: the memo's key is
`{maxW}|{maxH}|{scopeKey}` (solver.luau:2122) and a nested chain offers a
different `maxH` at every level, so every re-measure of the same node is a
different key. **Routed as evidence, not acted on** — `src/layout/solver.luau` is
another agent's file this week.

### Lever 2, priced — and it reframes three capture sessions

Tier 2, Studio, warmed + ABBA, n = 150, on a 33-row windowed-list tree solved
through `solver.solve` with and without `reuse`.

**A/A control: two identical `reuse=off` arms, 0.3308 vs 0.3444 ms = 4.1 %.**

| | full solve | incremental | change |
|---|---:|---:|---:|
| off-window edit (insert ~475 rows below the window) | 0.3308 ms | **0.2182 ms** | **−34.0 %** |
| in-window edit (one visible row's value) | 0.3350 ms | **0.2205 ms** | **−34.2 %** |
| nodes arranged | 101 | **2** / 5 | −98 % |
| nodes skipped | 0 | **99** / 96 | — |

**L-27 found incremental layout inert on a resize. On a collection edit it bites,
hard.** A resize changes every constraint so nothing can be reused; an edit below
the window changes one number and 99 of 101 subtrees land on exactly the rect
they had. Tier 1 agrees in direction at −10 to −15 % against a 0.9 % control —
smaller because the headless arm times the whole set→refresh round trip, so
arrange is a smaller share of the denominator.

**AND THE THING THAT REFRAMES THE LAST THREE SESSIONS: the lab has been running
with incremental layout OFF.** `renderer.luau:1764` is
`incrementalEnabled = opts == nil or opts.incrementalLayout ~= false` — the
framework ships it **ON**, a surface opts *out*. The lab's own selector
(`settings.incremental`) defaults to **false** and `buildLuauUI` passes it
through. So **`collectionChurn.html`'s 26 solves at 9.384 ms each were 26 FULL
solves, in a configuration production does not ship.** Every collection number in
this log taken through the shared mount has the same caveat.

Not flipped here: the lab default is a selector with recorded captures behind it,
and changing what the shared mount measures mid-log is exactly the trade L-33 and
2026-08-15 both refused. The lever workload hard-codes the flag per arm (like
`extentArms` hard-codes `itemExtent`) so the A/B is two configurations rather
than one measured twice, and a negative control asserts the `off` arm skips
nothing.

### What the workloads deliberately do NOT claim

- **`text` is tier-1-only.** Headless text metrics are a stub, so its +335 %
  under Lune is not a regression signal for the engine, and the Studio
  solver-level probe cannot price it either (no adapter text seam). The arm
  exists so a device dump can.
- **`usPerArrangedNode` is not a MicroProfiler `LuauUI/arrange` occurrence.** The
  lab arm times the whole set→refresh round trip; the Studio probe times
  `solver.solve`. Both are comparable arm-to-arm and neither is comparable to a
  dump's ms/occurrence.
- **`partialSolves == 0` on a shape arm proves nothing about the flag**, and the
  check that claimed it was deleted after the mutation round showed it passing
  with the flag flipped: the provocation moves every rect, so nothing can be
  skipped either way. The load-bearing check is `arrangePerRep == 1`.

### Mutation evidence

Ten new cases in `tests/perf_lab.spec.luau`, each reddened one at a time
(`lune run tests/run_one perf_lab`):

| mutation | reddened |
|---|---|
| M1 — `shapeTree` ignores `kind`; every arm builds `flat` | *"the nine shape arms are NINE TREES"* |
| M2 — shape arms present with `incrementalLayout = true` | **nothing** — the check was vacuous and was replaced |
| M2b — the provocation writes the same padding every rep | *"every rep provokes exactly ONE full solve"* |
| M3 — both edit arms hard-code `incremental = false` | *"the incremental A/B is TWO configurations"* |
| M4 — the shape rep loop stops yielding | *"ONE LAP FITS A 60-FRAME WINDOW"* |
| M5 — the off-window edit lands inside the window | the A/B case + *"an off-window edit provokes ONE solve and NO structural sync"* |
| M6 — the arm pointer never leaves arm 1 | all three arm-selector cases |
| M7 — an arm renamed in the declaration only | *"the declared arms ARE the installed arms"* + the pre-existing workload invariant |
| M8b — the measure fan-out reported as a constant | *"the nine shape arms are NINE TREES"* |
| M9 — the no-passes guard dropped | *"a workload that declares no passes says so"* |
| M10 — `check_perf_place` row points at a module that is not there | `check_perf_place: FAIL` |

**M2 is the one worth keeping.** The obvious check — "an arm built with the reuse
path off must report zero partial solves" — passes with the flag flipped to
`true`, because the provocation moves every rect and the reuse path needs a
byte-identical rect to skip anything. It was a check that proved nothing, and it
was found by running the mutation rather than by reading it. A second one was
caught the same way: *"every rep provokes exactly ONE full solve"* failed on
**unmutated** source, because `scopeCount` is nil-safe and the default harness
installs a no-op profiler, so every count read 0. **Confirm the check passes
green before trusting that a mutation reddened it.**

### Residuals

1. **The measure fan-out at depth is not fixed.** 16.4 measures per arranged node
   at depth 30 against 2.0 at depth 1, and the memo produces zero hits on that
   shape. Routed to whoever owns `src/layout/solver.luau` next; the candidate is
   the cache key's `maxH` term.
2. **The lab's `incremental = false` default.** Every collection number in this
   log describes a configuration production does not ship. Flipping it is a
   deliberate decision with capture rows behind it, not a patch.
3. **`text` has no honest tier-1 or tier-2 number**, only a device one it has not
   been given yet.
4. L-35 residuals 1–4 are unchanged.

---

## L-37 — the depth lever, paid: the cache key carried an offer the answer never read

**Date:** 2026-08-15 · **Evidence tier: 1 (headless Lune) + 2 (Studio, real engine
Luau VM).** No device claim is made here. L-36 routed this as evidence; this entry
is the confirmation, the fix and the before/after.

L-36 found that **depth**, not size, is what makes `arrange` expensive — the same
240 leaves cost 8.7× more per arranged node under 30 nested stacks than under one,
and the mechanism was re-measuring (16.4 measures per arranged node against 2.0),
not placing. It also refuted the obvious fix: putting the deep tree inside a
ScrollView (`deepScroll`) arms the measure memo and produced **zero hits**. It named
a candidate mechanism read from the source and explicitly **not measured**: the
memo's key carries the offered height, and a nested chain offers a different one at
every level.

### 1. The candidate SURVIVED, and here is the measurement rather than the story

An instrumented build recorded, per node, every key `solver.measure` computed and
counted the distinct values of each key TERM. On the 30-deep arm (271 nodes, 4 696
measure calls, 17.3 per node):

| key term | distinct values per node |
|---|---:|
| `maxW` | **1.00** |
| `scopeKey` (hidden depth · container · fit probe) | **1.00** |
| `maxH` | **16.33** |
| the whole key | 16.33 |

**The key varied by the offered height and by nothing else** — on a tree of
`fixed`-height boxes whose measured size cannot depend on it. Same run with `maxH`
removed from the key: **271 distinct keys, one per node.** The candidate was right,
and it is the same defect L-9 fixed for a text leaf, one scale up: *the one field
that made every key unique was the one field the computation ignored.*

`deepScroll`'s zero hits are the same fact seen from the other side. The memo was
armed there; every lookup missed because every level asked a different question
about the same answer.

### 2. What shipped — three rules, each an answer to "what does this measure READ?"

`solver.memoPlan` classifies each node once per solve.

**`PLAN_HEIGHT_FREE` — cache it, leave `maxH` out of the key.** L-9's rule, no
longer restricted to text leaves. A node qualifies when its height type is `fixed`,
`content` or `minMax` (the three `resolveAxis` answers without reading its limit),
neither axis is `aspect`, its kind's content does not read `innerMaxH`
(`HEIGHT_COUPLED_KINDS` = `scroll`, `fits`, `composition`, `grid`, `gridrow`,
`vwrap` — `hwrap` is NOT one: `flowPlan` breaks it on the width), and every child
qualifies, with no `fill`-main or `shrinkWeight` child on a vertical main axis
(PASS 2 and PASS 1.5 read `mainLimit`, which is `innerMaxH` there).

**`PLAN_SKIP` — do not cache a constant.** Both dimensions `fixed` means
`resolveAxis` returns two literals, `content()` is never called and nothing is
published: the key string and the entry table cost more than the measure they save.

**The memo arms on NESTING as well as on a ScrollView.** `hasScroll` was a proxy
for "this tree re-measures"; nesting is the other producer, and a scroll-free deep
tree could never reach the cache at all. `ctx.deepNesting` latches when the measure
recursion first reaches `MEMO_ARM_DEPTH = 4`, on the way down.

Plus one allocation cut: a cache entry for a node that publishes no verdicts (every
kind but `text` and `composition`) is the array `{w, h}`, read back in two indexes
instead of four replay assignments.

### 3. Where the constant 4 comes from — swept, not chosen

Tier 1, same 240 leaves, only the nesting depth varying, interleaved ABBA against a
**2.9 % A/A control**:

| nested containers | 1 | 2 | 3 | 4 | 6 | 10 | 20 | 30 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| delta | +0.0 % | +2.1 % | −12.4 % | −20.8 % | −34.5 % | −49.9 % | −69.1 % | −77.2 % |

A measure recursion of 4 is a root, two containers and a leaf — the shallowest tree
the memo is measurably worth arming for. **L-6's ruling stays intact:** the shape
arms that pay nothing (`flat`, `zstack`, `wrap`) never arm, and unconditionally the
memo ran them **+8 % to +20 %** against a 1.5 % control.

### 4. Before/after on the `arrange-shapes` arms — control stated first

**Tier 2 (Studio, real engine, ABBA-interleaved, n = 40×24 per arm). A/A control:
worst arm 1.74 %. Nothing below that is a result.**

| arm | HEAD | shipped | delta | HEAD uncached measures | shipped |
|---|---:|---:|---:|---:|---:|
| `flat` (control) | 1.1237 ms | 1.1289 ms | +0.5 % | 723 | 723 |
| `zstack` | 1.1842 | 1.1978 | +1.2 % | 963 | 963 |
| `wrap` | 0.8752 | 0.8758 | +0.1 % | 483 | 483 |
| `fill` | 2.2771 | 2.2529 | −1.1 % | 963 | 963 |
| `scroll` | 1.5512 | 1.3439 | **−13.4 %** | 725 | 725 |
| `deep` | 7.1384 | **1.2489** | **−82.5 %** | 4 696 | **529** |
| `deepScroll` | 9.3295 | **1.6638** | **−82.2 %** | 4 698 | **783** |

**Tier 1 (headless Lune, regression signal only), same instrument shape. A/A
control 1.2 %:** `flat` +0.3 %, `fill` +0.2 %, `zstack` +0.6 %, `wrap` +0.0 %,
`text` +0.2 %, **`scroll` −31.7 %, `deep` −77.2 %, `deepScroll` −83.1 %.**

`scroll` improves with its uncached count **unchanged**, which is `PLAN_SKIP` alone:
the memo had been spending more on filing constant-size leaves than the leaves cost
to measure. That is a defect L-9 shipped and nobody had priced.

**Through the lab's own arms** (tier 1, `tools/lune/_probe_levers`, forward sweep so
absolute levels drift between processes — normalised to each run's own `flat`
control, A/A 2.4 % before and 2.7 % after):

| arm | measures per arranged node | ×`flat` cost |
|---|---|---|
| `deep` | **17.33 → 1.95** | 3.12× → **1.38×** |
| `deepScroll` | **16.28 → 1.89** | 4.53× → **1.38×** |

The fan-out was quadratic in depth (4.30 / 8.32 / 17.33 measures per arranged node
at 4 / 12 / 30 levels). It is now flat (2.35 / 2.05 / 1.95).

### 5. Correctness — a differential oracle, and the gap L-9 recorded is now closed

800 seeded trees over the whole vocabulary (`fits`, `hwrap`/`vwrap`, `gridrow`,
`shrinkWeight`, `compactText`, `lineLimit`, `hug`, degenerate viewports), solved by
a HEAD build and the shipped one, comparing x/y/w/h **and** `compact`, `textState`
and `textFacts` per node: **25 961 node comparisons, ZERO differences**, and the
diagnostic SET identical on every tree (only duplicate counts differ, which is the
memo doing what it already did for scroll trees).

**L-9 could not build a case where an over-broad rule bites** and shipped its
exclusions on a line-by-line reading, recording that honestly as a known gap. The
richer oracle bites immediately: the fully over-broad rule diverges on **2 933 of
25 961** node comparisons, first at seed 1. Each exclusion was then mutated
separately and auto-shrunk, and all three reproductions are transcribed into
`tests/measure_memo.spec.luau`:

| exclusion removed | node comparisons that diverge | shrunk case |
|---|---:|---|
| the height-TYPE test (accept `fill`/`percent`/`hug`) | 2 303 | a `hug` anchor in a scroller: n15 74 → 258 |
| `HEIGHT_COUPLED_KINDS` emptied | 14 | a `vwrap` in a scroller: n5 215×169 → 115×175 |
| the `fill`-main / `shrinkWeight` child test | 25 | a squeezed `vstack`: n56 245 → 36 |

### 6. Mutation evidence

| mutation | reddened |
|---|---|
| M1 — the height-type test dropped | *"a `hug` height READS the offer"* (only) |
| M2 — `HEIGHT_COUPLED_KINDS` emptied | *"a `vwrap` breaks its lines ON the offered height"* (only) |
| M3 — the `fill`/`shrinkWeight` child test dropped | *"a child that can be SQUEEZED…"* (only) |
| M4 — `maxH` put back in the key | both fan-out checks + the perf-lab L-37 pin + *"NINE TREES"* |
| M5 — the nesting arm closed (`MEMO_ARM_DEPTH` huge) | the same four |
| M6 — the `PLAN_SKIP` branch deleted | **nothing** — see below |
| M7 — `levers.shapeTree` ignores `kind` | *"NINE TREES"* |

**M6 is the one worth keeping.** Declining to cache is never *wrong*, only slower
or faster, so no correctness test can pin `PLAN_SKIP`; its whole evidence is the
interleaved A/B. The solver says so at the rule rather than letting a future agent
assume a green suite covers it.

### 7. The bench, and the instrument trap inside it

`tools/bench.sh`, interleaved ABBA, **both builds on the same filesystem** (the
first attempt ran HEAD from `/private/tmp` and the shipped build from the Dropbox
working tree, which is not a comparison): whole-run p50 **−3.0 %**, total heap
43 763 → 34 214 KB. Layout-bearing scenes: `billboard-nameplate-storm` −7.5 %,
`table-mutation` −5.7 %, `table-resize-drag` −3.5 %, `mounted-slice-update-storm`
−0.3 %, `textinput-typing-storm` +0.7 %. No scenario newly flags.

**And a warning for the next person to read this bench.** `settings-churn-custom`
read **+52.8 %** and reproduced across eight interleaved runs with no overlap — a
convincing regression, except that **the scenario never calls the solver**: it is
signals, a memo, an observe and a dispose. Its sibling `settings-churn-fusion` read
−23.0 % in the same pair. What moves is `heapDeltaKb`, which flips sign between
builds: the collector lands in a different 5-microsecond scenario each run and that
scenario is billed for it. On these sub-10-microsecond core scenes the bench is
measuring GC attribution, not the change. The p50 SUM over the whole run is the
number that survived scrutiny.

### 7.5. The live-engine canary, and the trap it walked into first

Same Studio session, `ReplicatedStorage.LuauUI.layout.solver` confirmed byte-current
with the commit (178 598 chars, both sides), a 12-level chain of 4 leaves per level
solved through the real engine VM: **arranged 61, uncached measures 119, fan-out
1.95** against a headless 2.05 and a pre-fix 8.32. Root rect 400x600, geometry sane.

**The first run of that canary read 8.18 — the pre-fix number — on source that had
the fix in it.** `require` on a ModuleScript is CACHED per datamodel, and the Edit
session had already required the solver before the Rojo sync landed. The string
check on the Source passed while the running module was the old one, which is the
"a dump is not a witness for its own behavior" class in a new costume: *reading the
right source does not prove you ran it.* Cloning the package and requiring the clone
forces a fresh module identity and gives the real answer. Any future Studio A/B in a
long-lived session has to do the same.

### 7.6. The consumer rider (root CLAUDE.md)

`games/RascalRally/code/tests/luauui_measure_fanout_contract.spec.luau`, RR
`181a0ee`, suite **3234 passed / 0 failed**. It pins `controller.stats()`'s
`lastArranged`/`lastMeasured` on two real shipped surfaces and is mutation-proved
against this framework change — re-coupling the key reddens both, closing the
nesting arm reddens the ScrollView-free modal only.

**It deliberately claims the smaller thing.** Rascal Rally's surfaces are shallow —
the racer list arranges 37 nodes and the role-pick modal 9 — so the fix is worth
73 -> 61 and 35 -> 21 uncached measures there, not 82%. The rider proves the live
consumer is current and would catch the mechanism returning; the 82% lives on trees
this game does not build, and the device dump is what will say whether the game's
real screens are any deeper than these two.

### 8. Residuals

1. **L-36 residual 1 is closed.** The fan-out at depth no longer rises with depth;
   `tests/measure_memo.spec.luau` pins that it cannot start rising again.
2. **`MEMO_ARM_DEPTH` is a threshold, and thresholds rot.** The swept break-even is
   real but it was measured on one tree family on one laptop. A device dump of the
   `arrange-shapes` arms is what would confirm it on ARM.
3. **The lab's `incremental = false` default** (L-36 residual 2) is unchanged.
4. **`text` still has no honest tier-1 or tier-2 number** (L-36 residual 3).
5. **The memo still allocates a table per cached node per solve.** On a small tree
   with few repeats that is the whole of its cost. A one-slot inline entry with
   promotion on the second distinct key would remove it; not built, because no
   measurement has yet shown it is worth the code.
6. L-35 residuals 1–4 are unchanged.
