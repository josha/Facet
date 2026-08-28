# ADR-0056 — a lane that gave way is shorter at BOTH ends

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0056. A defect fix, not a new surface — no new prop, no new key, no
ADR-0040 row (no required-prop flip, no documented-default change). It DOES move
painted geometry on every composition that declares `exclusions`; the affected
shipped surfaces are listed under "What moves" below.
**Companions:** [ADR-0046](ADR-0046-band-safe-content-and-lane-exclusions.md)
§4 (the per-lane exclusion this corrects the other half of),
[ADR-0025](ADR-0025-screen-anchored-hud.md) (the composition's partition
guarantee, which this restores),
[ADR-0027](ADR-0027-platform-chrome-band.md) (why the top of a lane is a floor
rather than a margin).
**Home:** `src/layout/composition.luau` — the placement pass's `slack`.
**Guards:** `tests/composition_exclusions.spec.luau` (the §8 "shorter at BOTH
ends" block, 8 cases), `tests/overflow_sweep.spec.luau`
(`laneContainmentViolations` across the HUD matrix, plus its own mutation
control).

## Context

The director reported the same screen twice, five days apart:

> **1.** FIX the PS5 overlap bug — reproduced.
> **13.** overlap.png: screen-anchored HUD now overlaps at the bottom ON A
> PHONE. Same family as #1? **The framework should make overlap impossible —
> say why it isn't.**

Both captures show the same thing: the showcase's screen-anchored HUD with the
demo chip row declared as `exclusions`, and the kill-feed line painted on top of
the caption below the HUD's own box. Task FIX-4 reproduced it live on the PS5
preset and staged a headless repro, but did not close the mechanism: it measured
54px of overflow headlessly against 78-90px live and declined to guess at a
shared layout primitive on an unreconciled number.

### What §8 got right, and the half it forgot

ADR-0046 §4 gives a `Composition` an `exclusions` list: rects, in the
composition's own space, that a host's persistent chrome occupies. A lane whose
own content shares an x range with one of them GIVES WAY — it starts below the
rect instead of at the top of the lane band. Decided once, from the richest
forms, never re-asked (there is no convergence loop and no latch).

The lane's RECT was correct from the day that shipped, and a case has always
pinned it:

```
inset    = max(0, exclusionBottom - laneBandY)
laneRect = { y = laneBandY + inset, h = laneBudget - inset }
```

The lane starts `inset` lower and is `inset` shorter. Its bottom edge does not
move. Rule 3's overflow arithmetic knew this too — `laneOver` has always been
`laneNeed - (laneBudget - laneInset)`.

What the PLACEMENT pass then shared out among the lane's groups was

```
slack = laneBudget - laneNeed          -- WRONG: the lane before it gave way
```

— the slack of the lane the composition *would* have had if the host declared no
chrome at all. `place` turns that slack into the spacer run that puts a `start`
group at the top, a `center` group in the middle and an `end` group against the
bottom; `sizing = "fill"` takes it as height. Both readers were given one extra
`inset` of room that does not exist.

So every group in a lane that gave way was pushed down by its share of one
`inset`, and an `end`-placed group — `bottomLeft` / `bottom` / `bottomRight`,
whose share is all of it — landed **exactly `inset` px past the bottom of its own
lane**. On the PS5 capture that is the kill feed, painting over the caption
underneath the HUD.

### The number, and the reconciliation FIX-4 left open

Measured on the pure module (`bottomLeft` cluster, HUD preset, 1716x871 box):

| exclusion reach | lane rect | feed bottom | overshoot |
|---:|---|---:|---:|
| none | y=0 h=871 | 871 | **0** |
| 1x1 far away | y=0 h=871 | 871 | **0** |
| 1 | y=1 h=870 | 872 | **1** |
| 20 | y=20 h=851 | 891 | **20** |
| 54 | y=54 h=817 | 925 | **54** |
| 69 | y=69 h=802 | 940 | **69** |
| 141 | y=141 h=730 | 1012 | **141** |
| 300 | y=300 h=571 | 1171 | **300** |

The overshoot is the inset, 1:1, at every size — which is what identifies the
term rather than fitting a curve to one screenshot. FIX-4's 54-vs-78/90px gap is
the SAME single term read in two frames: its headless repro injected the chip
rect relative to a box whose origin was the window origin, while the live path
shifts window-space rects into a composition box that starts at y=-87, so the
live inset is 87px larger; and its "78px" was the group's TOP measured against
the box's bottom, not the group's bottom. One term, three arithmetics.

### Why the framework did not make this impossible

ADR-0025's guarantee, quoted from `composition.luau`'s own comment, is that
*"regions cannot overlap as BOXES: lanes sit side by side and a lane stacks its
groups down, which is the whole reason a HUD built on this mechanism cannot
produce the commissioning screenshot."* That guarantee is a claim about the
PARTITION, and it held right up until §8 made the partition's cells movable and
moved only one of the two edges.

Three separate detectors were watching and none could see it, each for a precise
reason:

1. **The overflow ladder** (`laneOver`, rules 3-5) compares a lane's NEED with
   its budget, and already subtracts the inset. This content FIT — 136px of
   cluster in an 817px lane. Nothing to reject, nothing to step down. Measured:
   `legal = true`, `fallback = false`, `rejected = 0`, with a region 300px
   outside its lane.
2. **The collision finding** (ADR-0025 Decision 3) needs a region whose chosen
   form MEASURES bigger than the box it was allotted; it is gated on exactly that
   precondition for cost. Every region here measured exactly its allotment.
   Measured: `collisions = 0`.
3. **The settle-time containment finding** (`placement_audit.containment`) is
   scoped by measurement to a STACK's cross axis. Its own header records the
   sibling class as booked, not shipped: *"a composition REGION placed below its
   composition's own content box fired 312 times on one scenario"* — and
   `tests/lib/overflow_guard.luau`'s header records why it was left alone: *"every
   one of the 312 carries `fallback = true` ... a LEGAL composition cannot produce
   one (measured at the boundary: the arrangement is rejected the moment a form
   outgrows the box)"*.

That last sentence is the answer to the director's question. There WAS a guard for
this exact shape. It was switched off on a premise that was true of the corpus
when it was measured (2026-08-21) and false of the mechanism — because the
premise reasoned about a form OUTGROWING its box, and this is a region placed
outside a box it fits in. Nothing anywhere compared a placed rect with the lane
rect it was placed into.

## Decision

**The slack a lane shares out is the shortened lane's, measured against the lane's
own rect.**

```luau
local slack = math.max(0, laneRect.h - p.laneNeed[i])
```

One operand, and it is READ FROM THE RECT rather than recomputed: `laneRect.h` is
`laneBudget - inset` by construction two lines above, so the two halves of the
give-way cannot drift apart again. With no exclusion declared, `laneRect.h` IS
`laneBudget` and every composition in the library places byte for byte where it
did (pinned as an additivity case, including the trivial-1x1-rect arm FIX-4 used
as its discriminator).

**The general property this establishes**, and the one the guard asserts: *after
giving way, a lane places its groups exactly as an unshortened lane of the same
height would — offset by where it starts and by nothing else.* Pinned for all
three `place` values at two insets, by comparing a shortened lane against a
literally shorter one.

**The 2-cycle constraint is untouched.** `composition.luau`'s documented design
rule is "decided once, never re-asked" — the exclusion decision reads the richest
forms on the first pass and is never revisited, so a reservation cannot be bought
back by a narrower form. This change adds no decision, no pass and no read: it
is one arithmetic operand inside the placement walk, downstream of every
decision, using a rect that walk had already computed. The fixed-point cases
(`re-resolving the same declaration twice lands on the same answer`) are
unchanged and still green.

**And the detector is turned back on, at the scope the measurement supports.**
`tests/overflow_sweep.spec.luau` grows `laneContainmentViolations`: across the
HUD device matrix × theme packages × text preferences × both strip states, no
mounted region of a LEGAL composition may sit outside the lane rect it was
placed into. Scoped to `legal and not fallback` for the reason the 312-case count
gives: a fallback composition already files its own designed finding and
re-reporting it is re-telling. The collector carries its own mutation control
(move one zone in a dump of a lane that actually gave way; assert it is reported;
assert the untouched tree is silent) because this sweep had already read one
silent zero for two director rounds.

## What moves

Painted geometry changes on **any composition that declares `exclusions` AND has
a non-`start`-placed group in a lane that gives way**. In this repository:

- `examples/gallery/scenarios/hud.luau` — the screen-anchored HUD, the reported
  surface. Its `bottomLeft`/`bottom`/`bottomRight` clusters (health, kill feed,
  actions, clock, buttons) move UP by the chip row's reach on the columns the
  chip row covers; `left`/`center`/`right` (centre-placed) move up by half of it.
  Only with the showcase's chip row declared, i.e. inside the showcase host.
- Nothing else. No other shipped scenario, example, reference app or proof
  declares `exclusions`, and a composition that declares none has an inset of 0
  on every lane, where the new operand and the old one are the same number.
- **Rascal Rally: not affected.** Its one shipped composition
  (`ResultsScreen.luau`'s `ResultsBody`) declares no `exclusions` and the game
  never publishes `appChromeRects` — grepped, zero hits, and pinned as a consumer
  rider in `tests/facet_composition_collision_contract.spec.luau` alongside a
  POSITIVE CONTROL that drives the game's own pinned Facet through an exclusion
  and asserts the containment, so "unaffected" cannot rot into "untested".

## The alternatives

**Clamp the group at the lane's bottom edge.** Rejected: a clamp turns a wrong
number into a right-looking one and hides the next arithmetic error behind it —
and it would silently overlap the group above it whenever the content genuinely
did not fit, which is the case rule 3's ladder exists to handle honestly.

**Push the exclusion into `laneBudget` instead of `laneRect`.** Rejected: the
budget is shared by every lane (it is what the SPANS left) and the inset is
per-lane. Subtracting a per-lane number from a shared one is how the two would
diverge again, in the other direction.

**Report it as a finding and leave the geometry.** Rejected outright — the
director's words are *"the framework should make overlap impossible"*, and a
diagnostic is not an impossibility. The finding ships too, as the guard, because
the fix makes the class impossible by arithmetic and the guard is what proves the
arithmetic did not come back.

## The runnable checks

- `tests/composition_exclusions.spec.luau` — 8 cases: the PS5 shape, the phone
  shape, the 1:1 inset sweep, the `fill`-sizing sibling, the shortened-lane
  placement invariant across all three `place` values, the silent-solver pin
  (legal AND contained), the additivity control, and the mounted-path phone case
  through the renderer. Seven were RED before the fix and are GREEN after; the
  additivity control passes in both, which is what makes it a control.
- `tests/overflow_sweep.spec.luau` — `laneContainmentViolations` in the HUD
  chrome sweep, plus `LANE-CONTAINMENT CONTROL`.
