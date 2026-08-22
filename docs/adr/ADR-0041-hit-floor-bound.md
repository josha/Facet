# ADR-0041 — A touch floor grows until it meets something the author made pressable

**Date:** 2026-08-21
**Status:** Accepted
**Number:** 0041. 0040 is the unreleased-breaking-changes register, whose row
**B-19** is this decision's entry there; 0031 is a burned number
([ADR-0032](ADR-0032-nested-instance-tree.md) records why).
**Companions:** [ADR-0039](ADR-0039-ten-foot-metric-ladder.md) (the ladder the
floor's value climbs, and the "floors clamp UP" rule this obeys),
[ADR-0019](ADR-0019-theme-packages.md) §2 (the metric the floor reads),
`src/render/hit_lift.luau` (the paint-order half, and the doctrine R23 extends),
`tests/hit_floor_region_clamp.spec.luau` and `tests/overflow_sweep.spec.luau`
(the two guards), `docs/handoff/SOURCE_CAP_LEDGER.md` (why the fix waited for a
split).

## Context — a floor that was the width of a whole region

A control under the effective touch floor is given an invisible hit expander
inflated around its solved rect. For a chevron that is a ~44 px column at a
region's trailing edge and it overhangs nothing that matters. For a **cover** —
the affordance a stepped-down region grows when nothing in its reduced form
carries meaning — the solved rect **is the region's whole box**, so inflating a
20 px-tall region to the floor necessarily leaves the region by 12 px above and
below, across its full width. The engine delivers input to the topmost object
only.

Measured in `region_expand.spec`'s `ringScreen` fixture at 390×150: **960 px² of
`/S/C/Before/First` and 828 px² of `/S/C/After/Last` — 26 % of each button** —
delivered to the plate instead of to the button the player aimed at. That is the
one-gesture-two-meanings collision R18 exists to prevent, arriving across a
region boundary instead of inside one (DIR5 review H1).

## Decision — the floor grows, one side at a time, and each side stops

`render/commit_walks.growWithin(own, want, blockers)` gives a node the floor it
asks for **one side at a time**, each side stopping at the first blocking rect in
its way, and **never handing back less than the node already paints**.

Both halves are load-bearing. The stopping is the fix. The never-shrinking is
what keeps the fix from being a worse defect than the one it closes: a host box
that does not contain its own child — an anchored node, a negative offset — would
otherwise produce a hit rect smaller than the rect the player can see.

**A box to clamp into was tried first and the measurement refused it.** The
prescribed design bounded a cover to its region. On the shipped HUD demo three
stepped-down covers whose floors reach nothing at all lost the floor entirely,
purely because their regions are 21–30 px tall, and `overflow_sweep`'s *no
dead-end compact* guard reported it on **five viewports**: a route the thumb
cannot land on is a route on paper. The guard was right; the container was the
wrong bound.

## The two bounds, and who ruled each

### R18 — the AUTHOR-content bound

The controller's R18 splits by **what is underneath**: the floor is **exempt over
passive content** — 44 px is the F1 accessibility floor and the convention every
platform ships, and clamping it to a mark's own reserved column would put a
below-floor target on the one thing on the row that exists to be tapped — and
**banned over interactive content**, because two live targets for one gesture is
an ambiguity the player cannot see.

So an **ordinary sub-floor control keeps its whole floor**, including the part
that leaves its parent. Only the population whose rect is a *whole region* is
bounded at all.

### R23 — the FRAMEWORK-vs-FRAMEWORK bound (2026-08-21)

R18 answered the author-content question. It was never asked whether the
framework should surrender the accessibility floor to **its own** synthesized
affordance. **R23: it should not.** The blocker set holds only rects the
**author** declared; framework affordances may overlap one another and arbitrate
by the existing paint order.

That is not a new principle — `hit_lift`'s doctrine already draws the same line
on the same question: *"expander-vs-expander is left to the existing host z
order… another expander's invisible rect never [creates a lift]."* A cover paints
not one pixel; two of them meeting is an ordering question the z walk already
decides.

**The ruling was measured, not preferred.** Counting the framework's own routes
as blockers, over the `overflow_sweep` matrix (viewport × theme package ×
preference × strip state):

| | framework counted as a blocker | R23 |
|---|---|---|
| route boxes swept | 381 | 381 |
| below the effective floor | **43** | **38** |
| …attributable to a framework route | **20** | **0** |
| covers retracted entirely | 32 | 31 |
| smallest route | **25 px** | **35 px** |

The 25 px route sat **one pixel above** `overflow_sweep`'s 24 px dead-end bar —
a silent accessibility regression that nothing in the suite would have reported.

## What this does not decide

* **Whether a region should be at least a floor tall in the first place.** The
  R18 hit-floor reserve — reserve the mark's width *plus* the floor's overhang in
  the solver — is still booked on `SOURCE_CAP_LEDGER`'s solver row. With it, a
  cover could never be boxed in at all, and this rule would stop firing on
  shipped screens. This ADR is the renderer-side half.
* **The remaining 38 sub-floor routes.** Every one is cut by an author node, and
  each is legitimate under R18: the author put a control there. They are pinned
  as a set, not as a count.
* **Anything on a device.** This is a touch-target change; the 35 px routes are
  what a device round is for.

## Consequences

* A cover boxed in on every side has **no hit expander**; its affordance is the
  region's own box, which is what it painted all along.
* Two adjacent covers' floors may **overlap each other**. That is R23's explicit
  allowance, and the z walk decides between them exactly as it did before.
* The blocker set is a per-solve linear pass over `inputSinks` **per standing
  cover** — the same census `hit_lift` already consumed, whose value now records
  *who declared the sinker* rather than merely that one exists.

## Guards

* `tests/hit_floor_region_clamp.spec.luau` — the rule at fixture scale: the DIR5
  numbers as 0 px², the HUD's three covers keeping 44 px, the F1 exemption in two
  forms, a hidden blocker in two arms, and `growWithin` itself as a table of
  cases. 8 mutations proved to bite.
* `tests/overflow_sweep.spec.luau`, *"R23: no route falls below the touch floor
  except where an AUTHOR node is in the way"* — the rule at **matrix** scale, over
  all 381 swept routes, with the per-side attribution derived independently of
  the rule it audits. 4 mutations proved to bite, in both directions.
* `tests/region_expand.spec.luau` EXPAND 15 — no interactive node under either
  role's floor, in its own region or a neighbour's.
