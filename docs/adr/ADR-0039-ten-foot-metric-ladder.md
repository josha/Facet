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

That identity is what makes the acceptance **falsifiable rather than eyeballed**, and
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
you read is that ladder with the distance policy applied.** `env:set` normalises
through `themes.baseOf` so the fact always holds a base, and the transform is always
derived FROM the base rather than composed onto its own output — which is what makes
a display-class change exactly reversible even for a pixel package, whose lengths
snap onto an integer grid in both directions. At every near display the read is the
**identity**: the same table, not a copy, so nothing near moves by a pixel and the
common path allocates nothing.

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
