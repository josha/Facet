# ADR-0051 — The thickness/metrics family (framework-gaps-phase2, wave 3-B)

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0051. 0050 is the composition/env family (wave 3-A, no ADR-0040
row); 0049 is content-terms height. This decision adds TWO rows to the
ADR-0040 register — **B-28** (item 42, the focus-ring inset) and **B-30**
(item 34, the decorative-chrome floor) — plus item 19's own row landed in
the round's first pass as **B-29**. See "What is breaking, and what is not".
**Companions:** `.superpowers/sdd/framework-gaps-phase2/task-w3b-brief.md`
/ `gap-registry.md` items 42/29/34/19 (the mission), `artifacts/
release-candidate-review/t16-triage.md:39` and `.superpowers/sdd/
release-candidate-review/task-plate-b-report.md` (item 42's source
evidence — the ring-room shortfall this decision closes), `.superpowers/
sdd/framework-gaps-phase2/binding-context.md` §"Gap 35 source row" (the
same evidence, carried verbatim for this round), [ADR-0039](ADR-0039-ten-foot-metric-ladder.md)
(the `densityClassOf` ladder this decision's `controls.focusRing.*`
exemption extends), [ADR-0042](ADR-0042-app-metric-namespace.md) (cited in `themes/snapshot.luau`'s own "the
app namespace" section — the `metrics.tenFoot` absolute-override channel
item 42 rides rather than re-invents), `tests/authoring.spec.luau`'s F-20/
BP-F12 (item 29's pre-existing metric-name-grammar proof, found rather than
built).
**Home:** `src/themes/snapshot.luau` (`controls.focusRing.{thickness,inset}`,
`controls.decorative.minimum`, `controls.badge.minimum`, `resolve`'s
"4a-focus"/"4a-decorative"/"4a-badge"/"4b-focus"/"6a" steps,
`densityClassOf`'s `controls.focusRing.*` exemption), `src/layout/
expand_plate.luau` (`CLOSE_INSET`, `RING_THICKNESS`), `src/render/
layout_node.luau` (the `surface = "badge"` intrinsic-minimum default),
`src/blueprint.luau` (`DividerSpec.thickness`/`PathSpec.thickness` →
`Bound<number | Metric>?`).
**Guards:** `tests/region_expand.spec.luau` (the ring-inset mirror-parity +
universal-guarantee test, red-first against the measured shortfall),
`tests/ten_foot_metrics.spec.luau` (the proportion-equality sweep's
`controls.focusRing.*` exemption), `tests/path.spec.luau` (Path.thickness's
own paint+ten-foot proof), `tests/authoring.spec.luau` (gap 19's
undimensioned-floor/explicit-dim-wins/surface-scoped describe block),
`tests/overflow_sweep.spec.luau` + `tests/theme_matrix_audit.spec.luau`
(the full sweep, item 34's own evidence). RR: `tests/facet_racer_list.
spec.luau` (badge-icon rect-size pin against the new floor default).

## Context

`gap-registry.md`'s thickness/metrics family, four items assigned one round
(`task-w3b-brief.md`): three registry items (29, 34, 19) plus gap 42, the
focus-ring metric booked for phase-2 in `t16-triage.md` and carried into
this round with the director's word already given. Two items (42, 29) are
an explicitly PAIRED pattern — "the same construct one over": both are a
STROKE/RING prop that only ever accepted a raw pixel value, with no way to
name a theme metric. One item (34) named two independently-hardened
fixtures with no consumer sites given. One item (19) gave no consumer
sites at all and required a census before any build decision was legal.

## Decision

### 1. Item 42 — `controls.focusRing.{thickness,inset}`, mirroring the
   style authority the layout side could not see

The ring's real authority has always been `style.extra.focusRingThickness`
/ `tenFootFocusRingThickness` — but that is the STYLE side, and the metric
SNAPSHOT (the one thing `layout/expand_plate.luau` can read) answered nil
for it. `expand_plate.CLOSE_INSET` — the close disc's own inset from the
panel's corner, "the room the focus ring draws in" per its own header —
had always spent `space.xs` instead: a spacing step with no relationship
to the ring it exists to clear. The prior round (`task-plate-b-report.md`)
measured the consequence and could only NAME it: `classic_desktop`/
`compact_pointer` at ten-foot, `space.xs` 3 against a 4px strengthened
ring, 1px short — asserted as a two-way ratchet rather than closed.

`themes/snapshot.luau`'s `resolve()` now mirrors the style authority (the
package's own theme entry, falling back to `default_style` — the exact
"fill" semantics `sheet_model.buildPackage` already uses) onto two new
metric-tree leaves:

* `controls.focusRing.thickness` — the ring's own number, deliberately
  UNSNAPPED at every display class. It mirrors a second paint authority
  that was never on the package's pixel grid, so pixel-snapping it would
  make the metric disagree with what `screen_target.luau` actually paints
  — measured live on `pixel_quest`: the generic per-package pixel-snap
  sweep rounds a raw `2` up to its 4px grid, producing a metric reading `4`
  while the ring itself still paints at `2`. Written AFTER the pixel-snap
  step (`resolve`'s "4b-focus"), not before, for exactly this reason.
* `controls.focusRing.inset` — `math.max(space.xs, ring)`, at both rungs of
  the ladder, and DOES pixel-snap: it is a real spent layout distance
  (`expand_plate.CLOSE_INSET` names it directly, replacing `"space.xs"`),
  so it belongs on the package's own grid exactly as `space.xs` does.
  `snapToPixelUnit`'s UP-rounding is monotone, so snapping the max of two
  raw numbers lands on the same answer as snapping each input first —
  proved by construction, not merely asserted.

The ring does not ride the generic `metricScale` 1.5x ladder — it
STRENGTHENS (2 → 4, not 2 → 3), the "focus strengthening" row `metricScale`'s
own header names as one of the ten-foot policy's four rows, alongside the
type floor. `densityClassOf` classifies the whole `controls.focusRing.*`
family "exempt" from the generic per-leaf multiply; its ten-foot VALUE is
an absolute injection seeded into `resolve()`'s `tenFoot` table (step "6a"),
applied by the pre-existing `forDisplay` machinery — the SAME channel
`metrics.tenFoot` already gives a package for "I want an absolute ten-foot
number, not a derived one" (the vocabulary `resolve`'s own `overrides`
parameter and B-25/B-26's `space.tight`/content-terms rows already spend).
A package's own `metrics.tenFoot` entry for either path still wins over
this round's seed — the escape `t16-triage.md` itself named ("or those
packages re-spec their ring") — because the package's loop runs after the
seed and its assignment is unconditional.

**Effect.** `math.max` means every package whose own `space.xs` already
cleared the ring (Studio Neutral: 4/6 against 2/4; seven of the nine
shipped packages `tests/region_expand.spec.luau`'s corpus sweep checks)
gets the IDENTICAL inset back, byte-for-byte — confirmed by
`check_flat_baseline`, zero new drift. Only `classic_desktop`/
`compact_pointer`'s ten-foot inset moves, 3 → 4px, closing the measured
shortfall by construction rather than by a named ratchet. RascalRally is
unaffected: its own theme package (`TableMetrics.typePackage`) authors no
`space` section at all, inheriting Studio Neutral's `space.xs = 4`, already
proven to clear the ring at both rungs by the same corpus sweep — a
compatible internal change, no RR-side edit needed.

`tests/region_expand.spec.luau`'s prior-round ratchet test (a hand-named
list of short packages, asserted in both directions) is replaced with two
live assertions instead: the metric MIRRORS the style authority exactly, at
every package and class (a parity guard against future drift between the
two authorities), and the disc's inset clears the ring UNIVERSALLY, with no
named exceptions.

### 2. Item 29 — `UI.Path.thickness` metric channel: found already built,
   the residual gap closed

Investigated before writing anything, per "the same construct one over"
framing: the runtime plumbing already existed.
`blueprint_schema.luau`'s `Path.thickness` prop already declared
`types = {"number", "metric"}` — its own comment reading "same ruling as
Divider.thickness" — and `render/renderer.luau`'s `applyProp` already
resolved a string thickness against the live snapshot at the paint write
seam. Three real production consumers already spell it:
`p2_cartwheel/screens/dashboard.luau:406`, `ledger.luau:86` (`thickness =
"controls.table.indicatorThickness"`), `p1_glade/ui/scene.luau:133,145`
(`thickness = "xs"`). `docs/reference/api.md` already documented the
grammar. `tests/authoring.spec.luau`'s F-20 (BP-F12) already proved the
metric grammar CONSTRUCTS for both Divider and Path, and that a bogus name
refuses naming the vocabulary.

What was actually missing, and what this round closed:

1. **The static type disagreed with the runtime contract.** `PathSpec.
   thickness` (and `DividerSpec.thickness` beside it — the same defect,
   found by the pairing) were typed `Bound<number>?`, literally excluding
   the metric-name string the schema and renderer both accept, while every
   OTHER metric-capable prop in the same file (`gap`, `padding`) already
   uses the established `Bound<number | Metric>?` shape. Widened both to
   match. Not CI-enforced today (`tools/check_types.py` is deliberately
   narrow to `src/init.luau` plus one witness file), but a real inaccuracy:
   the three production consumers above were already spelling a shape their
   own declared type forbade.
2. **No proof existed at the seam Path actually uses.** F-20's own "SOLVES
   to the theme's number" case covers ONLY Divider, because Divider
   consumes `thickness` at the SOLVER (it never reaches an adapter, and the
   case reads a `rect.h`) while Path consumes it at PAINT — a different
   seam, with no owed proof at all. Added one: `tests/path.spec.luau`
   mounts a metric-named Path at Medium and Large, asserts the adapter's
   painted `thickness` equals the independently-resolved snapshot number at
   each class, and that Large's painted number is strictly greater than
   Medium's — the ten-foot-scaling FACT, not merely two resolutions that
   happen to differ.

**Verdict:** DISPOSED-with-measurement, not BUILT — there was nothing left
to build. RR calls `UI.Path` extensively with numeric thickness only; the
type widening is purely additive and breaks nothing there.

### 3. Item 34 — `controls.decorative.minimum`, the theme-owned
   decorative-chrome floor two fixtures hardened by hand

Found the two fixtures the registry names: `examples/gallery/scenarios/
time_curves.luau`'s `PUCK_PX`/`LANE_PX` (both `= 40`, the fixture's own
comment: "THE PUCK IS 40px BECAUSE THE SWEEP SAID SO... 40px is the size
`with_animation`'s puck already proves") and `with_animation.luau`'s
"Lane"/"Puck" (`px = 40` twice) — the SAME number, independently hardened
against `tests/overflow_sweep.spec.luau`, exactly the audit's evidence. A
`control`-chrome package (fantasy-ornate, fantasy-parchment, glossy-touch,
pixel-quest) wants 28px of its own border on one axis alone, so an
undersized decorative box (no content of its own to measure, unlike a
label) cannot spend its theme's insets and draws smaller than the theme
expects.

Shipped `NEUTRAL_DECORATIVE_MIN = 40` — byte-identical to what both
fixtures already used — as `controls.decorative.minimum`, filled for every
package the way `iconSizes` already is (an authored override wins, the
framework default otherwise), riding the generic `controls.*` "scale"
density classification with no new snapshot bookkeeping beyond the fill
itself: this is a plain metric, not a mirror of a second authority the way
item 42's ring is. Migrated both fixtures' literal `40`s to the metric NAME
`"controls.decorative.minimum"` — accepted anywhere a `px` value is, the
same mechanism `expand_plate.CLOSE_DISC` already spends.

**Effect.** Byte-identical at Studio Neutral/Medium (40 either way,
confirmed via `check_flat_baseline`, zero new drift); NEW scaling at
ten-foot — the raw literal never rode any ladder, the metric now scales
1.5x like every other `controls.*` length (40 → 60). Booked as ADR-0040
**B-30**: a real, MEASURED 20px growth on two shipped example fixtures, in
the safe direction (a floor growing, never shrinking), swept at
`console-ten-foot` (`displaySize = "Large"`, one of `tests/lib/
device_views.luau`'s VIEWS) by `overflow_sweep.spec.luau` with zero new
findings — the direct, mechanical test of the lesson this decision exists
to apply: a theme-owned floor must ten-foot-scale, and the sweep is what
proves a token swap changing WHAT scales did not silently regress a
scenario that already cleared it.

### 4. Item 19 — `controls.badge.minimum`, built on a census the audit
   never gave

`gap-registry.md` names item 19 with "Not specified by audit" for both home
and consumer sites — the brief's own instruction was census first, build
only if consumers prove the need. Found 9 real `surface = "badge"` sites
across Facet and RascalRally:

| Site | Explicit dim? |
|---|---|
| `src/controls/picker.luau:611` (option count) | yes — `BADGE_BOX = {minMax, min="l"}` |
| `examples/gallery/scenarios/adaptive_controls.luau:308` | yes — fixed 28px |
| `examples/gallery/scenarios/hud.luau:959` | padding only, no dim |
| `examples/gallery/scenarios/native_style.luau:98` | yes — `UI.Image`, fixed `{px = 56}` on both axes |
| `examples/reference/p4_foyer/init.luau:566` | yes — `{minMax, min=BADGE_MIN(20), max=BADGE_MAX(40)}`, comment: "a count bubble is a MIN-SIZED round plate, never a bare glyph hugging its own pixels" |
| `examples/reference/p1_glade/ui/shop.luau:109` | **none** |
| `examples/reference/p2_cartwheel/screens/parts.luau:117` | padding only, no dim |
| RascalRally `FacetRacerListScreen.luau:118,130` (x2) | yes — fixed 20px |

8 of 9 independently reserved room by hand, in three different shapes
(fixed dims, a `minMax` floor/cap pair, hand padding); `p4_foyer`'s own
comment states the exact defect this item names. Consumers proved the
need.

Shipped `controls.badge.minimum` (20px neutral — the value two of the five
explicit-dim sites converged on independently), filled the same way as
item 34's floor. Applied at `render/layout_node.luau`, keyed on
`props.surface == "badge"` — a SURFACE concern, not a class one; Text,
Image and ZStack all wear the skin in shipped fixtures — rather than
joining the per-class chain: when NEITHER `width` nor `height` is authored,
both default to `{type = "minMax", min = badgeMin}`. An explicit dim still
wins, the same `or` idiom every other default in that function already
uses.

**Effect.** Byte-identical for every census site carrying an explicit dim
(8 of 9). The one shipped site that left it fully bare — `p1_glade/ui/
shop.luau`'s Nectar-card count, corner-anchored inside a ZStack — now
measures at least 20px on each axis instead of hugging a one-digit
numeral's own glyph box. Booked as ADR-0040 **B-29**.

## What was rejected

**Replacing `space.xs` outright with `controls.focusRing.inset` for EVERY
package** (item 42), rather than `math.max`-ing the two. Simpler code, and
considered seriously — but it would have moved Studio Neutral's own
straddle/corner geometry (4 → 2 near, 6 → 4 far) for zero measured benefit,
breaking the "byte-identical unless a shortfall was actually measured" bar
the rest of this campaign holds. `max` is the minimal-blast-radius fix the
brief's own "make the two shortfall packages resolve honestly" asked for —
seven of nine packages move nothing.

**A brand-new top-level metrics section for the ring**, instead of
`controls.focusRing`. Rejected in favour of the existing open `controls.*`
vocabulary (mirroring `controls.table.*`, `controls.slider.*`), which needs
no new `DENSITY_*` bookkeeping beyond the one family-scoped "exempt"
carve-out `densityClassOf` already required for the ring's own
strengthening law.

**Pixel-snapping `controls.focusRing.thickness` the same way every other
`controls.*` leaf is snapped** (item 42). This was the FIRST shape shipped
mid-round and was found wrong by running the suite, not predicted:
`pixel_quest`'s own corpus sweep (`tests/region_expand.spec.luau`'s
mirror-parity case) caught the metric disagreeing with the paint authority
(`4` read back where the ring still paints `2`) before it shipped. Split
the write into two steps instead — `inset` before the pixel-snap pass,
`thickness` after — rather than exempting the whole family from snapping
(which would have left `inset`, a real spent layout distance, off the
package's own grid).

**A `max`/cap pair for `controls.badge.minimum`** (item 19), mirroring
`p4_foyer`'s own hand-rolled `BADGE_MIN`/`BADGE_MAX` (a pill that grows for
"99+" but stays round for one digit). Rejected as scope creep beyond what
the census's OWN evidence demands: a MINIMUM floor is what closes "a bare
glyph hugging its own pixels" (the stated defect), and a max-capped pill
shape is `p4_foyer`'s own design decision, not a fact every badge site
needs — `{type = "minMax", min = badgeMin}` leaves a badge free to grow
past the floor for wider content, without imposing a cap nobody asked the
framework for.

## What is breaking, and what is not

**Three rows.** Item 42 — ADR-0040 **B-28**: `expand_plate.CLOSE_INSET`
names `controls.focusRing.inset` instead of `"space.xs"`; two shipped
packages' ten-foot inset moves 3 → 4px, closing a measured shortfall.
Item 19 — ADR-0040 **B-29**: `surface = "badge"` gains a 20px intrinsic
floor when undimensioned; one shipped site's real geometry moves. Item 34
— ADR-0040 **B-30**: two gallery fixtures' decorative floor now
ten-foot-scales, 40 → 60px at `displaySize = "Large"`. All three are
MEASURED, not guessed, and all three move in the SAFE direction (more
room, never less) per each row's own arithmetic.

**Item 29 is purely additive.** `DividerSpec.thickness`/`PathSpec.
thickness` widen from `Bound<number>?` to `Bound<number | Metric>?` — a
type accepting a strictly larger domain than before, with the runtime
behaviour it now correctly describes unchanged (the schema and renderer
already accepted and resolved the string; only the exported TYPE catches
up). No prop flipped to required and no documented default changed value.
No row.

## Registry evidence

Per the round's own instruction: build, or dispose with measurement —
evidence first, never assumed.

- **Item 42** — BUILT (§1 above). Red-first against the measured shortfall;
  green with a universal guarantee replacing the prior round's ratchet.
- **Item 29** — DISPOSED, measured (§2 above). Found already built by prior
  work; the residual static-type and paint-seam-proof gaps closed in this
  round.
- **Item 34** — BUILT (§3 above). Two independently-hardened fixtures
  migrated to a real theme token.
- **Item 19** — BUILT (§4 above), on a nine-site census the audit itself
  gave none of.
