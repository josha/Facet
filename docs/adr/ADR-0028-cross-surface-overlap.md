# ADR-0028 — Cross-surface overlap: the alarm reads DECLARATIONS, not geometry

**Date:** 2026-08-14
**Status:** Accepted
**Commissioned by:** the game director, 2026-08-14, watching a leftover debug probe interleave with
a real fixture in his live Studio session, both starting at x=16. Verbatim: ***"the framework should
stop this from happening."***
**Companions:** ADR-0025 Decision 3 (`resolution.collisions` — the same alarm one level down, and
the shape this one reuses), ADR-0026 Consequences (the hand-off this ADR takes, and the constraint
that decides its central question), `docs/lessons/the-solver-already-told-you.md` (why a new failure
class must be *reported*, and why a diagnostic the sweep cannot see is a diagnostic nobody runs).

## Context — the gap, stated exactly

ADR-0025 gave `UI.Composition` a collision alarm: for every mounted **region** it takes the painted
box, reports every unordered pair whose boxes intersect, and files one diagnostic per pair. It works
**inside one composition**, because a composition is one solve of one tree.

Nothing looked at **two independently mounted surfaces**. That is not an exotic case — it is what a
real game has constantly. A HUD, a modal, a toast layer, a debug overlay: each is its own
`renderer.attach`, its own controller, its own solve. `presenter.luau` alone raises eight kinds
(base screen, modal, scrim, popup catcher, disclosure plate, reveal overlay, drag proxy, toast
layer), and `src/controls/row_actions.luau` raises a ninth without going through the presenter at
all. Any pair of them can cover any other, and **no code in the repo could see it**: each solver
sees one tree, and the presenter's `stack` is a closure-local list nothing reads for geometry.

The director's report is the cheap version of the expensive bug. His was a probe he had left behind;
the shipped version is a modal that failed to dismiss, a toast layer that outlived its surface, or a
second base screen presented over the first because a route fired twice.

## Decision 1 — the predicate, which is the whole design

> **Fire when two live surfaces on one paint target both COVER something, their cover rects
> intersect, and NEITHER declared that it means to cover the other.**

Cross-surface overlap is **not** a defect by itself. A modal *should* cover a HUD; that is what a
modal is for. A scrim covers everything on purpose. What is a defect is two surfaces on top of each
other that nobody ordered, because then *which one a player sees is an accident of mount order* —
and that is a sentence a framework can say and a screenshot cannot.

So the alarm reads **declarations**, and every word of its vocabulary already existed.

**`rootPolicy = "edgeToEdge"` is a declaration.** The renderer's own comment on the enum is the
argument: *"edgeToEdge: a DECORATION layer, not content. Safe areas exist so content is readable and
reachable; a scrim or a backdrop is neither"* (`renderer.luau`, `ROOT_POLICIES`). Every one of the
seven `edgeToEdge` call sites in `src/` is a scrim, a catcher, a floating plate or a drag ghost. It
is a declaration on **either** side of the pair, because a scrim means to cover *and* means to be
covered — the catcher the presenter mounts at `owner.displayOrder - 50` sits underneath its owner
and is silent for exactly the same reason the scrim above it is.

**A different display BAND is a declaration.** `presenter.SURFACE_LAYER` is
`{ base = 10000, toast = 20000, dragProxy = 30000, modal = 40000 }`, and its own header says why
they are bands rather than a counter: *"a toast has to sit above every base screen and below every
modal regardless of the order they were presented in, which a single monotonic counter cannot
express."* Two surfaces in different bands are layered on purpose. Two in the **same** band are not:
within a band the presenter simply steps `+100` per surface, which is arrival order, not intent.

**An UNSET display order declares nothing at all**, and this is the clause that catches the
commissioning bug. `controller.setDisplayOrder` is optional; a surface raised by a bare
`renderer.attach` and never ordered has said nothing about where it belongs. So `displayOrder` on the
scan descriptor is `nil` until something sets it, and `nil` is not a band — "nobody ordered this
surface" and "this surface is at layer 0" are different declarations and must not share a value.

**Why symmetric.** The brief's rule is "neither declared", and it is the right rule rather than
"the upper one declared". Covering looks directional, but the escape hatches are not: `edgeToEdge`
is used both by things that go over content and by things that go under it, and a band difference is
a fact about the pair. A directional rule would have made the scrim-under-its-owner case fire, which
is the single most common two-surface arrangement in the framework.

**What is deliberately NOT a declaration.** `deviceSafeContent` is an inset choice, not a layering
one, and a surface that opts into the notch insets has said nothing about who is on top of it. It is
pinned as a case, because the tempting shorthand — "any non-default `rootPolicy`" — would have made
the alarm silent on exactly the surfaces most likely to be wrong.

## Decision 2 — a surface's COVER RECT is what it paints, and ADR-0026 is why

ADR-0026's author left a constraint in its Consequences, and honouring it is what makes this
mechanism correct rather than merely plausible:

> the set of "I am not covering anything" declarations is now bigger than `rootPolicy`/`edgeToEdge`.
> A surface at `opacity = 0` occupies its box and covers nothing visible, and `hidden` is the same
> shape. A geometry-only diagnostic would report a collision no player can see.

The naive cover rect is the surface's **root rect**, and it is wrong twice over. It is wrong for
ADR-0026's reason — a faded surface still has a root rect — and it is wrong for a second reason the
first one exposes: a `UI.Screen`'s rect **is the content rect its `rootPolicy` resolved**, so it is
*the same box for every base screen on the device*. An alarm built on it would report every pair of
base surfaces at full-screen size and would be measuring the device, not the screens.

So the cover rect is **the union of every painted box below the root**:

```
coverRect = ⋃ { rect(p) : p ≠ rootPath, rect(p) has area, nothing on p's ancestor chain paints nothing }
```

and "paints nothing" is one predicate over the ancestor chain, asked of three facts the renderer
already keeps: `hiddenRoots[p]` (which merges the authored `hidden` prop with the solver's own
hidden verdicts), `paintHeld[p]` (the presenter's paint veto), and `lastComposedAlpha[p] ≥ 1` (the
composed engine transparency — which is `1` for an authored `opacity = 0`, for a framework fade to
nothing, and for any product of the two that reaches it). An ancestor is enough because a fade group
is its subtree's real instance parent (ADR-0022 Decision 2), so a group at `T = 1` genuinely hides
everything inside it.

**This is the payoff of taking the constraint seriously.** Four separate "covers nothing" cases —
`hidden`, `opacity = 0`, a live exit fade, and a root switched off by the no-pop text gate — are
answered by *one* union rather than by a list of four special cases, because **a node that paints
nothing contributes nothing to a union**. A surface with nothing left has no cover rect at all, and a
surface with no cover rect is in no pair. Each of the four is a named case in
`tests/surface_overlap.spec.luau`; deleting the alpha clause reddens the `opacity = 0` case by name,
and deleting the hidden clause reddens the `hidden` one.

**What the union does NOT claim, said plainly.** A container that `fill`s its box contributes its
whole box, so a HUD whose one visible element is a corner badge still claims the screen. That is
deliberate and it is the honest answer: a fill container may put its content anywhere in that box, at
any viewport, any text preference and any theme package — and this repo's own always-on sweep exists
because content moves under exactly those axes. A cover rect measured from today's badge would go
green on a screen that is one text-size step away from a collision. It is pinned as its own case so
the limit is a decision on the record rather than a surprise.

## Decision 3 — it is an INSPECTION API, not a solve-time finding, and the cost is therefore zero

The brief asked whether this runs at solve time or on inspection. **Inspection**, and not as an
optimisation — as the only correct answer:

- **A cross-surface fact is not a property of any one solve.** It changes when *another* surface
  mounts, moves, fades or leaves, which this surface's solve cannot see. Filing it at solve time
  would leave it stale on one side of every pair and duplicated on the other, and would need an
  invalidation channel between controllers that exists for nothing else.
- **The cost when nothing overlaps is not "small", it is zero**, and that is provable rather than
  assertable. Nothing in this ADR runs in a solve, a commit, an arrange or a frame. A surface pays
  one table write when it attaches and one when it leaves.

**The proof is a test, not a claim.** `surface_overlap.scans()` counts pairwise passes, and
`tests/surface_overlap.spec.luau` asserts that sixty `presenter.refresh()` calls on a target holding
two overlapping surfaces perform **zero** of them. Deleting the `< 2` precondition reddens the
adjacent case by name. That guard is worth more than a perf-lab arm here, and is why no perf-lab
scene was added: a lab row measures a cost this mechanism does not have, while the counter fails the
day somebody puts one on the frame path.

**Neither a solver finding nor a presenter diagnostic — a SURFACE finding.** The solver is a pure
function of one tree and structurally cannot see a second one. The presenter is not the only thing
that mounts surfaces (`renderer.attach` is public, and `row_actions` uses it directly). The renderer
is where a surface *is*, so the registry lives beside it and the finding arrives through
`controller.diagnostics()` — the one channel every consumer already reads, and the one ADR-0025's
class travels on. `presenter.SURFACE_LAYER` stays exactly where it is; `surface_overlap.bandOf`
derives the band width from it and a test reads the presenter's real table and fails if the two ever
disagree, so there is a derivation with a pin rather than a second copy.

**Full cover and partial overlap are different, and the sentence says which.** A pair whose rects
merely intersect is reported as *"surface 'A' overlaps surface 'B' by 200x120px"*; a pair where one
rect contains the other is *"surface 'Backdrop' completely covers surface 'Panel' (200x120px)"*.
They are different bugs — one clips a corner, the other hides a screen — and an author reading the
first will look for the edge while an author reading the second will look for the dismiss that never
fired. Both carry the same remedy list, because the remedies are the same: declare the layer,
declare the decoration, hide it, or dismiss it.

**One sentence per pair, filed on BOTH surfaces.** ADR-0025 could name an offender — the region
painting outside its own box. Here both surfaces are inside theirs and the defect is that nobody said
which is on top, so there is no offender to name and the sentence is identical on both sides. Filing
it on both is also what makes it *reachable*: `tests/overflow_sweep.spec.luau` holds only the
surface a fixture returns, and a one-sided finding on the newcomer would be invisible to it.

## Decision 4 — the alarm's set of live surfaces is the PRESENTER's set of live surfaces

Found by the corpus, not by design, which is the part worth recording.

The hour the alarm landed, `tests/reference/sipworks_spec` went red on eight compact cases.
`p3_sipworks` pushes one full-screen detail over another — `dismiss` the outgoing, `presentModal` the
incoming — and `presenter.dismiss` takes a surface out of `stack` **now** and tears its tree down
**later**, when the exit transition finishes or the coordinator's 500 ms cap fires. In that window a
departing screen is fully painted over its replacement, which is the transition doing its job.

The fix is not an exception for transitions. It is that the two sets must be equal:
`controller.retireSurface()` drops the registry entry, and `presenter.dismiss` calls it on the same
line as `setFocusPath(nil)` — the call that already says "this surface has stopped being a surface,
whatever is still on screen". `controller.dispose()` calls it again for every surface that never went
through a presenter at all.

This is also the first thing this mechanism ever caught, and it caught a *framework* fact rather than
a fixture bug — which is the argument for running a new diagnostic against the whole corpus before
believing its predicate.

## What the corpus said

The predicate was counted across the corpus before it was believed, which is the discipline
ADR-0025's own rejected `UI.Anchor` alternative asks for.

| | |
|---|---|
| the whole suite, alarm live | **one** finding class, on `p3_sipworks`, 8 cases — the transition window above |
| after Decision 4 | **zero** unexplained findings anywhere: 43 swept surfaces × 8 viewports × 4 text preferences × 8 theme packages, plus the 5 reference proofs and 7 tutorial examples |
| the waiver list | **unchanged** — nothing was waived to make this green |

Zero is the right number and it is not a weak result: every multi-surface arrangement the framework
itself builds is already declared (seven `edgeToEdge` surfaces, a banded toast layer, banded modals),
which is the evidence that the vocabulary chosen was the vocabulary the framework was already using.

**And the sweep can see it — checked rather than assumed.** The showcase fixture's default
declaration was flipped from *layered* to *undeclared* and
`overflow sweep: scenario 'surface_overlap'` reddened with **112 findings** across the cross product,
naming both surfaces and the box, at every viewport and preference. Restored, and green.

## Cost, measured — tier: HEADLESS LUNE, a regression signal and never a device claim

The instrument drives `renderer.attach` directly against the pre-change module read out of git
(`git show HEAD:src/render/renderer.luau`, required side by side), strictly alternating arms, 15
pairs, min per arm, on a 24-row scrolling surface at 390x844.

**The control first, three runs, before any delta is quoted** — the same LIVE module in both arms:

| arm | same-arm spread |
|---|---|
| `refresh()` (a dirtying signal + a re-solve) | **0.06% / 0.29% / 0.60%** |
| mount + attach + first render | **0.53% / 0.65% / 2.16%** |

...and then the A/B:

| | before | after | delta |
|---|---|---|---|
| `refresh()` | 595.2 / 598.1 / 601.5 µs | 594.2 / 605.8 / 601.7 µs | **−0.18% / +1.29% / +0.02%** |
| mount + attach | 1302.5 / 1353.5 / 1301.9 µs | 1312.2 / 1338.4 / 1320.8 µs | **+0.74% / −1.12% / +1.45%** |

Every delta is inside the same-arm spread band. **This instrument cannot resolve either change**,
which is the expected result: the frame path gained no code at all, and attach gained one table
write and one closure. The refresh row is the one that matters, and it is the row the `scans()`
counter turns from a measurement into a permanent test.

The inspection path itself, live only (there is no "before" — the work did not exist):

| `controller.diagnostics()` | per call |
|---|---|
| one surface on the target | **0.071 µs** — the precondition, and the whole cost of the overwhelmingly common case |
| two surfaces, ~170 nodes each | **146 µs** — two cover-rect unions plus one pair test |

A two-surface `diagnostics()` read is about a quarter of one re-solve, on a call that is a diagnostic
read by definition and never on a frame. The pair scan is O(surfaces²) of pure arithmetic over a
population that is single digits.

## The Studio canary — OWED, and the reason is structural

**No live canary ran, and this says so rather than glossing it.** Checked rather than assumed: the
one connected Studio instance is `LuauUI-PerformanceLab.rbxl`, and `script_grep` for a string written
in this task returns nothing while the datamodel's `screen_paint` still carries the pre-extraction
line numbering — so that session is not syncing this tree, and no result read from it would have been
about this change.

More to the point, **this mechanism cannot be live in any session yet**: it is wired in
`src/render/renderer.luau`, which is 238 000 characters against Studio's 200 000-character `Source`
limit. ADR-0025 hit the identical wall for the identical reason (`solver.luau`, 214 000) and recorded
it the same way. The pure module and the fixture are both far under the cap; the wiring is not, and
no push route gets around a limit on the write itself. The canary is owed, and it is owed to the
renderer's file size rather than to this ADR — which is one more concrete cost for the standing
"renderer.luau is past an agent's reach" refactor flag.

What stands in for it meanwhile is stated plainly so nobody mistakes its tier: the whole corpus
headless (43 surfaces × 8 viewports × 4 preferences × 8 packages), the sweep watched reddening with
this exact class, twelve mutations, and Rascal Rally's own rider driving the game's real chip band
through its shipped `present` opts.

## Consequences

- **Public surface added:** `controller.coverRect()` (what this surface paints, or `nil`),
  `controller.retireSurface()`, and a new finding class on `controller.diagnostics()`. MINOR bump;
  additive — a target with one surface on it produces byte-identical diagnostics, and the finding is
  **not** `designed` (it describes two things on screen at once, which no author asked for) so every
  consumer reading the `designed` field handles it correctly on day one.
- **`src/render/surface_overlap.luau`** is a new pure module (≈310 lines): the pairwise scan, the
  band derivation, the union, the sentence, and a weak-keyed live registry bucketed by paint target.
  The weak-key pattern is the one `src/client/theme_controller.luau` already uses for
  `liveControllers`. Two surfaces on two adapters are two windows and can no more overlap than two
  devices can.
- **A registry entry is a leak if it is not dropped**, and the check that proves it exists because a
  mutation proved the line did *not* need proving any other way: deleting `unregisterSurface()` from
  `dispose()` reddened nothing, because a disposed controller answers a `nil` cover rect anyway. What
  it changes is that a long-lived `PlayerGui` accumulates one dead entry per mount forever. The case
  asserts `surface_overlap.count(target)` instead, and now reddens.
- **The showcase demo is the mechanism, because the pixels cannot be.** `scenarios/surface_overlap`
  mounts one probe surface over one screen in four states — layered, decoration, undeclared,
  invisible — that paint **identical pixels**. Only the declaration changes, and only the
  framework's own sentence tells them apart, read straight off `controller.diagnostics()` with no
  interpretation in between. Registered in `scenarios/init.luau` ORDER, in `demo_picker.DEMOS`, and
  swept. Its probe is scope-owned and dismissed on every path including dispose — which is not
  incidental tidiness, since a probe surface left behind is the thing that commissioned this ADR.
- **Twelve mutations, twelve named cases.** Every clause of the predicate, both halves of the
  covering set, the registration, the retirement, the precondition, the both-sides filing and the
  zero-area epsilon were each broken in turn; each reddened a case that names it.
- **What it cannot see, stated rather than left to be assumed:**
  1. **Z-order within a band.** The alarm reports that two surfaces are unlayered; it does not know
     which the engine will paint on top, because that is the accident it is reporting.
  2. **Partial transparency.** A surface at `opacity = 0.5` covers, and is reported as covering. Only
     *nothing* is nothing. The corollary, found by the Rascal Rally rider rather than reasoned to: a
     surface with a `materialize` transition is born at `GroupTransparency = 1` and therefore covers
     nothing **until its enter transition lands**. That is correct — it is transparent — and it means
     the alarm is quiet across an enter fade at both ends, matching Decision 4's answer for the exit.
  3. **Two targets.** Surfaces on different adapters never see each other, by construction. A game
     painting one logical screen through two adapters is outside this alarm.
  4. **The engine's own overlays.** CoreGui, the topbar and the platform's controls are not LuauUI
     surfaces; `rootPolicy` and ADR-0027's `platformChrome` are the vocabulary for those.
- **RascalRally consumer pass:** the game mounts one presenter and its surfaces are the presenter's
  own banded and `edgeToEdge` ones, so the lockstep obligation here is a compatibility proof rather
  than a port — the game's screens report no cross-surface finding, pinned in the game's own suite.

## Alternatives considered

- **A solve-time finding, filed into `ctx.diagnostics` like ADR-0025's.** The obvious symmetry, and
  wrong for the reason Decision 3 gives: the solver is a pure function of one tree, so the fact would
  have to be injected into it from outside, would be stale on whichever side solved first, and would
  put work on the frame path for a question nobody asked that frame. The finding still *arrives* on
  the same channel, which is the half of the symmetry that was worth keeping.
- **A geometric test on the root rects.** Cheaper and O(1) per surface, and it fails ADR-0026's
  constraint on its first line. It also degenerates: every base screen's root rect is the same
  content rect, so the alarm would fire on every pair at full-screen size and teach people to skim
  the suite — the failure mode the waiver list's rule 3 exists to prevent.
- **A new `covers` / `overlay = true` blueprint prop.** A third way to say what `rootPolicy` and the
  display bands already say, and a fourth place for them to drift apart. Rejected at rung 1 of the
  simplicity ladder: the brief's own observation is that the vocabulary already exists, and it does.
- **Reporting the pair on the upper surface only.** Directional, smaller, and it makes the alarm
  invisible to the always-on sweep (which holds the base surface) and noisy on the scrim-under-owner
  case. Symmetric is both more correct and more reachable.
- **A perf-lab scene row.** Rejected on the measurement: there is no per-frame code to measure, and a
  permanent lab row for a zero would be a check that proves nothing. The `scans()` counter is the
  guard instead, and it fails the day that stops being true.
