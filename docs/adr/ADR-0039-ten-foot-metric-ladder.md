# ADR-0039 — On a television the type grew and the chrome did not, so the chrome grows too

**Date:** 2026-08-20
**Status:** Accepted
**Number:** 0039. 0038 is the theme-tag vocabulary; 0031 is a burned number
([ADR-0032](ADR-0032-nested-instance-tree.md) records why).
**Companions:** [ADR-0019](ADR-0019-theme-packages.md) §2 (the resolution order this
extends, and the "floors clamp UP" rule the hit floor still obeys),
[ADR-0016](ADR-0016-three-axes-contract.md) (shape/input/display as the only axes),
`artifacts/release-candidate-review/adapt-audit/matrix.md` **ADAPT-8** and
`…/matrix-layout.md` **ADAPT-L1**/**ADAPT-L9** (the measurements),
`tests/ten_foot_metrics.spec.luau` (the standing guard).
**Supersedes:** the type-only ten-foot policy — the note in
`themes/snapshot.resolve` step 2 ("recorded, never re-applied") as a statement about
the *policy*, and the ten-foot paragraph of `docs/guide/07-input.md`, which described
a distance treatment of type, overscan, density and focus and no size ladder at all.
The `resolve` note remains true as a statement about `resolve`, and now says where
the application moved to instead.

## Context — four rows, and the fifth nobody had claimed

Facet's ten-foot treatment was four named rows: a **1.5× type floor** (body text must
clear ~29 pt at three metres), the **sizeClass/lane density cap**, a **strengthened
focus ring**, and the **overscan-safe margins**. The audit measured the consequence
plainly (ADAPT-8): control heights, paddings, gaps, icon sizes, corner radii and the
44 px hit floor on a television were **byte-identical to a phone's**. The audit was
careful to file this as a *scope question* rather than a defect — no acceptance row
ever claimed metric spacing scaled, and measuring the absence of an unpromised thing
as a bug is inventing a requirement — and put it to the director. ADAPT-L9 measured
the same thing one level down and more concretely: `gap = "m"` resolved to **16 px**
at 390×844 and to **16 px** at ten-foot 1920×1080, while the type in that gap was
already half again as large.

**The director ruled on 2026-08-20, against the audit's own keep-type-only
recommendation:** on ten-foot, controls, spacing, icons and hit floors scale with the
type, tvOS-style.

## Decision 1 — one factor, and the equality it buys

The metric ladder scales by **`tenFootFloor`** — the type floor's own 1.5 — read
through `themes.metricScale`, which is `typographyPaintScale` spelled for metrics.
The body of the function is one call to the same private constant, deliberately: two
constants that agree today are exactly how a 16-in-44 becomes a 24-in-60 the week
somebody tunes one of them.

That sharing is what makes the acceptance **falsifiable rather than eyeballed**, and
the director set the acceptance in those terms:

> every text-to-control proportion at ten-foot equals its near proportion.

A 16 px label in a 44 px control at arm's length is a 24 px label in a 66 px control
across a room. It is asserted across every scaled metric of all nine shipped
configurations, and separately as the ratio itself over six type roles and fourteen
control metrics — not on a screenshot, and not on the handful of metrics somebody
remembered.

**Why not a bespoke, larger factor for chrome** (the obvious alternative, and the one
a "TV needs bigger buttons" instinct reaches for): any factor other than the type's
breaks the equality above, and the equality is the only property of this feature that
a headless test can hold. A director who later wants a different chrome factor has a
named seam to change (`metricScale`) and an acceptance that will go red and say so.

**What the guard actually is** (corrected in fix round 1, from the wave's review).
The spec asserts that the two functions **agree on every value `displaySize` can
take** — the closed engine domain plus absence plus garbage — not that they are the
same function. They are deliberately two functions: sharing a factor is not sharing a
decision, and a caller reading the type seam's answer to size a button is spending the
wrong one. So `rawequal` on the two is false by design, and the property worth
guarding is agreement rather than identity. The reviewer confirmed the divergence this
Decision exists to prevent IS caught: tuning `tenFootFloor` while `metricScale` holds
its own literal reddens sixteen cases, including the proportion equality itself.

## Decision 2 — it is applied in the environment, not in the snapshot

`snapshot.resolve` records `density` and **still re-applies nothing**; the snapshot
remains the AUTHORED ladder. The distance policy is applied once, in
`themes.forDisplay`, called from the environment's `themeMetrics` memo — the same
seam, over the same `displaySize` fact, that already applies the type floor through
`typographyScale`/`typographyPaintScale`.

This placement is **ADAPT-L1's fix**, not an implementation detail. ADAPT-23 had
moved the lane cap into `adaptive.columnsFor` and had the solver pass
`ctx.metrics.density` — and that value is set in exactly one place, from the facts a
snapshot was *resolved with*. The environment's default `themeMetrics` is
`themes.neutral()`, resolved with no facts at all, and the only thing that
re-resolves it is a theme controller, which is an **opt-in install**. So a television
presented through plain `Facet.newPresenter` measured **10 lanes against a desktop's
9** while painting 1.5× type into them: the worst of both. Display facts must flow
without a theme opt-in, and display facts live in the environment.

The consequence for the key's contract, stated plainly because it is the one
surprising thing here: **what you set on `themeMetrics` is the authored ladder; what
you read is that ladder with the distance policy applied.**

The transform is always derived FROM the base rather than composed onto its own
output, and that is what makes a display-class change exactly reversible even for a
pixel package, whose lengths snap onto an integer grid in both directions. `forDisplay`
recovers the base itself, which is the line that guarantees it. **`env:set`'s
normalisation is a second, different guarantee** (the first draft of this ADR credited
it with the reversibility, which the wave's reviewer correctly measured as wrong —
deleting it changed nothing observable): it keeps the FACT holding an authored ladder,
which matters in the one shape where recovering and refusing diverge — a value read,
held across a swap to another package, and written back, i.e. exactly what
`theme_controller` does on uninstall.

And since `themes.baseOf` is an **identity** map, a caller that copies a read and
writes the copy back has lost the link. That used to apply the transform twice
(`targetSizes.minimum` 44 → 66 → 99). Such a write is now **refused**, warning once
and leaving the fact's last real value standing: writing it as a base double-applies,
and un-scaling by division is lossy on a pixel grid, so there is no third answer the
framework can compute exactly.

At a near display the read is the **identity** — the same table, not a copy — for
every snapshot resolved with no display facts, which is every snapshot on the default
path and every one a theme controller commits on a near client. So nothing near moves
by a pixel and the common path allocates nothing. (A snapshot resolved *with*
`displaySize = "Large"` and then read on a near display is the one exception: it
returns a corrected copy with `density` flipped to `"near"`. The numbers are right;
it is not the identity, because the live display class outranks the facts a snapshot
happened to be resolved with.)

## Decision 3 — what does not scale, and why each one is out

- **The type ramp.** `typographyPaintScale` already scales it at the measure and
  paint seams. Scaling `type.*.size` here as well is the 2.25× double application.
  The trap this rule exists for is `controls.table.cellTextSize` — a *type* size
  living inside a *control* family — so the classification is by name
  (`*TextSize`), not by section.
- **Durations.** Motion stays time-true at every distance; reduced motion is
  untouched. A 0.12 s fade is not 0.18 s on a television.
- **Viewport-relative layout.** A fraction of the screen is the same fraction at
  every distance.
- **The overscan margins.** They are their own ten-foot row and an *environment*
  fact, composed with the safe insets by the renderer. They compose; they must never
  multiply, or a console surface silently insets 135 px where two rows each thought
  they were the only one.
- **Corner radii and stroke thicknesses** (added by fix round 1, 2026-08-21, from the
  wave's review — NEW-1). These were in the scaled set when this ADR was first
  written, and that was wrong for a reason the wave had no instrument to see:
  they are not resolved from this snapshot at paint time. They come from `ctx.style`
  — `tokens/default_style.luau` on the default path, the package's authored metrics on
  the themed one — and `sheet_model.buildPackage` bakes them into StyleSheet rules as
  **literals**, a channel that never passes through `forDisplay` and cannot (one sheet
  per package serves every surface on the client, whatever display class each is on).
  So scaling them did not make a television's corners rounder; it made the MEASURED
  corner disagree with the PAINTED one — 12 painted against 18 measured on the default
  package, 10 against 15 under Fantasy Ornate, 14 against 21 under Glossy Touch — and
  the disagreement is load-bearing: `present/anchored.luau` shapes a callout tail from
  `radii.panel` and its seam from `strokes.hairline`. **The general rule this states:
  a metric may only scale where the framework OWNS the paint.** If the director later
  wants TV corners and strokes to scale, that is sheet-GENERATION work (a
  distance-aware rule set), not a reclassification — booked as a director-eye row in
  the batched Studio pass.
- **Art geometry** — `chromeInsets`, `chromeOutsets`, `chromeBleed`. This is the
  sharpest line in the classification and the one that took a measurement to find. A
  nine-slice border is drawn at `SliceCenter`/`SliceScale`, both authored by the
  package and neither varied by display class; a shadow's blur is a declared px
  figure the engine renders unchanged. Reserving 1.5× of a border that is still
  16 px wide is a reservation for pixels that **do not exist** — the exact inverse of
  the "painted at a size nobody measured" family this framework already names, and
  the reason a reservation must always be the number the paint will be. A slot
  `inset` is a composite (authored padding **plus** the art's own border, summed in
  `resolve`), and the framework already publishes the split, so the honest transform
  is `(inset − art) × factor + art`: a flat package's slot padding scales outright
  and an ornate package's frame stays the thickness it is drawn at.

An unclassified numeric metric is **exempt at runtime** — the safe direction, because
a new duration silently multiplied is worse than a new length silently not — and a
**suite failure**, so the gap is loud exactly once, at the commit that introduces it.

**One section is the exception, and it is the open one** (review NEW-4, recorded
2026-08-21). `controls.<family>.*` is an open namespace a package may author freely,
so it cannot be a list; it is a default of `scale` plus a suffix vocabulary of
non-lengths (`*TextSize`, `*Lines`, `*Count`, `*Duration`, `*Seconds`, `*Ratio`,
`*Fraction`, `*Scale`, `*Opacity`, `*Weight`). A future `controls.card.shadowBlur`
would therefore classify as `scale` and be multiplied, while the completeness rule
stays green because it *is* classified — and it would contradict the art reasoning
above, where a shadow's reach is exempt. All 46 current control-family leaves across
the nine shipped configurations are genuine lengths, so there is no live defect; a
new control metric that is not a length must be named so the vocabulary sees it.

## Decision 4 — authored beats derived

A package that means something specific about a television declares
`metrics.tenFoot`: dotted metric paths to **absolute** pixel values at distance, the
same vocabulary `themes.resolve`'s `overrides` parameter already takes. The derived
1.5 fills in wherever a package is silent — the rule `space.gutter` already spends.
A path that names no metric in that package's own resolved snapshot is refused at
resolve time rather than becoming a silent no-op on a television nobody in the studio
owns, and a declaration still may not defeat the accessibility target floor.

The section is optional and empty for every package shipped before this ADR, so no
package's authored metrics — and therefore no package's content `stamp` — moved.

## Consequences

- **The hit floor is 66 px at distance**, through one owner:
  `layout_node.effectiveHitFloor` reads `metrics.targetSizes.minimum`, and both its
  readers (the solve, which carries it so a result can name its interactive rects,
  and `pushHitRects`, which spends it as real hit geometry) follow the ladder without
  knowing the ladder exists. ADAPT-12 — "the 44 px floor is right for touch and
  unexamined at distance" — closes with this.
- **Every console-row pinned geometry moved**, and each was re-pinned citing this
  wave rather than silently rebaselined. The overflow sweep stayed green because
  layouts reflow; the cells that did not were real adaptation findings and were
  fixed in the fixture, not waived: three example surfaces and one reference app
  were spelling theme metrics as literals (`fixed 36`, `fixed 44`, an `8` copied
  from `space.s`, a 96 px band capping a control whose own chrome had grown), which
  is precisely the class the ladder was always going to expose.
- **Nothing near changed.** The near read is the identity, and the suite's near rows
  are byte-identical across the wave.
