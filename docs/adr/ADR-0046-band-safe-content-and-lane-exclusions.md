# ADR-0046 — The platform's band is a POLICY, and the host's chrome is a DECLARATION

**Date:** 2026-08-22
**Status:** Accepted
**Number:** 0046. 0040 is the unreleased-breaking-changes register; **this
decision adds one row there** — B-24, the `topbar` zone's geometry — and §"What is
breaking, and what is not" says why the rest is additive.
**Companions:** [ADR-0027](ADR-0027-platform-chrome-band.md) (the `platformChrome`
fact this spends), [ADR-0023](ADR-0023-declared-content-composition.md) and
[ADR-0025](ADR-0025-screen-anchored-hud.md) (the composition and the HUD preset),
[ADR-0040](ADR-0040-unreleased-breaking-changes.md) §B-24.
**Home:** `src/render/renderer.luau` (the policy resolver and the gutter floor),
`src/layout/solver.luau` (the content rect), `src/layout/composition_resolve.luau`
(the window→box conversion), `src/layout/composition.luau` (the band row and the
per-lane exclusion), `src/blueprint_schema.luau` (`UI.Composition.exclusions`).
**Guards:** `tests/band_policy.spec.luau`, `tests/composition_exclusions.spec.luau`,
`tests/hud_composition.spec.luau`, `tests/hud_chrome_rotation.spec.luau`,
`tests/hud_paint_probe.spec.luau`, and Rascal Rally's own contract specs.

## Context — a published fact nothing spent, and a band that was one rectangle

Two findings from the release-candidate framework audit, and they are one
problem seen from two sides.

**§9.** `platformChrome.bandInsets` has been a published fact since ADR-0027 and
`docs/reference/api.md` has described it as *"what a surface that means to ride
the band applies instead"* — but **no policy applied it**. `rootPolicy` was a
three-value enum guarding a four-case world: content inset by the CoreGui
reservation, content inset by the per-edge max of CoreGui and device, and
decoration painting to the glass. The fourth case — *content that means to sit
level with the platform's own controls* — had no spelling, so a surface that
wanted it had to present `edgeToEdge`, which drops all four insets, and re-spend
every one of them by hand.

Two shipped consumers did, and both said so in their own headers. The HUD demo
spent ~150 lines on it. Rascal Rally's chip band wrote: *"That row is the
PLATFORM'S TOPBAR STRIP, and it is outside every content-safe root policy by
definition."*

**And the hand-roll was better than the policy.** The HUD's version also floored
each edge against the theme's gutter, which `deviceSafeContent` did not — and
that floor exists because of a measurement, not a preference: on a device whose
engine pre-excludes the notch from the camera the lateral inset is ZERO, so
every edge-anchored control laid out flush against the camera boundary and a
rounded control whose rim ended exactly there read as one that had been cut.
The two orientations looked like opposite defects because the exclusion is
wildly asymmetric (1px of glass beyond a 401px portrait camera, 125px beyond a
749px landscape one). *When the consumer's hand-rolled version beats the shipped
policy, the policy is the bug.*

**§8.** A `Composition`'s lane band is one rectangle — every lane starts at the
same y — so a host's own chrome row covering SOME columns and not others could
not be reserved around declaratively at all. `src/env/environment.luau` documents
the punt in as many words: *"which is what lets a consumer reserve around it per
column."* The HUD demo did it by hand, and the cost is the part worth recording:
a `reachEpoch` dependency token naming every composition input by hand, a
monotone latch to bound a cross-frame geometry feedback loop, and a
majority-coverage floor for the frame before any geometry existed. Its own note
records what that cost on a real device: leaving the platform insets out of the
token latched a wrong answer for a whole epoch, and the centre column sat 62px
lower than a fresh mount of the same screen.

**A consumer maintaining a manual dependency set for a framework convergence
loop is the smell.** That is the finding, and it is why these two ship together:
the same fixture is the consumer of both.

## Decision

### 1. `rootPolicy = "bandSafeContent"` — the fourth case

The content rect is `platformChrome.bandInsets`: the same three edges
`deviceSafeContent` clears, and a TOP brought up to where the platform's FREE
strip starts. With no band reported the two records are equal, so a consumer
needs no branch and the policy is byte-identical to `deviceSafeContent` there.

The policy reads ONE env fact where the others read three, and its dependency
set says so: `platformChrome` replaces `coreSafeInsets`, `deviceSafeInsets` and
`overscanInsets` in the surface's geometry keys. That is the same narrowing
`edgeToEdge` already gets, in the other direction — a surface depends on exactly
what its policy reads. `platformChrome` is the one NESTED fact in that list and
it is compared by a comparator written beside the shape it knows; the standing
refusal to half-compare a nested fact stands for facts with no comparator.

The ten-foot overscan is NOT composed on top of it, and the asymmetry is a fact
rather than an oversight: `platformChrome` folds the overscan into both of its
inset records itself, so a second addition would spend a television's margin
twice.

### 2. `bandSafeContent` floors its other three edges at `themeMetrics.space.gutter`

The per-edge max of the platform's inset and the theme's gutter. The platform's
safe inset answers *"what must be cleared"*; it does not answer *"may content
touch the glass"*, and those are different questions.

`space.gutter` and not `space.s`: the screen edge is the one step in the scale
with a physical floor under it (the snapshot derives it as `max(8, space.s)`),
so a dense package cannot put content 4px from the glass and a package that
breathes more moves it.

**`edgeToEdge` is exempt, and that is the whole point of it.** It is the
decoration policy — a scrim or a backdrop *"has to paint to the edges or it
draws a rectangle inside the screen with the world showing around it"* — so a
gutter there would break the case the policy exists for. `tests/band_policy.spec`
carries that as a control rather than as a comment.

**The top of a band-riding surface is exempt too**, and that is the one thing
ADR-0027 exists to protect: its top edge is where the platform's own strip
starts, and a theme gutter there would stop the topbar row sitting level with
the engine's buttons.

#### Why only this policy, when the audit says "floor every policy"

**Measured, and the number is the decision.** The audit's clause is right about
the principle and this round could not land it: flooring `coreSafeContent` and
`deviceSafeContent` too costs every surface 16px of measure, and **the shipped
example corpus does not have it.** Built and run, `tests/overflow_sweep.spec.luau`
files **255 findings across 51 of its 95 scenarios** — 249 of them at the two
narrowest swept viewports (320x640 and 640x320) — which is content that no longer
fits its own box on the very device class the gutter exists to protect. Rascal
Rally's suite is nearly untouched (three pins); the gallery is not.

Re-tuning fifty-one example scenarios for a narrower content box is a campaign of
its own and a director's call, not a clause of this round. **The line that lands
it is one branch condition in `renderer.luau`**, and the measurement is booked in
`docs/handoff/G8G9-OWED-LIVE-WORK.md` §5 rather than left as a sentence.

WHAT IS NOT DEFERRED is the finding underneath it: the HUD demo's hand-rolled
version had the floor and the shipped policy did not, and the surface it rides is
`bandSafeContent`. That surface has it now, which is why the hand-roll could be
deleted rather than copied.

### 3. The `topbar` zone is laid into `platformChrome.band` by the solver

`composition.ZONES[1]` — the tenth zone, which is not one of the nine anchors —
is a `span = "above"` group, and under `bandSafeContent` it is the one span row
that is not full width: it is laid into the free strip's own `x`/`w`, and its
height reaches the band's bottom edge. So its content is level with the
platform's buttons and cannot be over them, by construction rather than by two
hand-computed spacers.

**A span row's slack goes to its `fill` regions** — rule 6, applied to a row
instead of a lane. Until the band existed a span row was exactly as tall as its
content, so there was never slack to give; the band row is the first whose height
is a platform fact, and `sizing = "fill"` in it means what it means everywhere
else.

**The lanes never start inside the platform's own reservation.** The row rides
the strip and the lanes start at the whole top reservation, which are two
different edges that coincide on a platform whose CoreGui inset is exactly its
topbar band. That is what makes the policy additive in risk: a composition that
declares no `topbar` region gets exactly the lane band `deviceSafeContent` would
have given it, so asking for the policy does not put anything in the band —
DECLARING A REGION does.

### 4. `UI.Composition{ exclusions = Readable<{Rect}> }` — the host's own chrome

Rects in WINDOW space, which is the space `platformChrome.rects` is stated in and
the space the solver's own output rects are in, so a consumer never converts and
never needs to know where its composition landed. A solved lane starts BELOW any
of them that its own regions share an x range with; a lane whose content clears
them stays level with the chrome.

**The rule is the MEASUREMENT, not a coverage fraction**, and the three fractions
that were tried are each wrong on a case this repository has measured:

* **any overlap** pushes the centre column down at 749x380 for 17px the centred
  clock never comes near — the director's own round-2 refusal;
* **majority** misses a 46%-covered right column whose `end`-anchored rail is
  inside the chrome row (measured at 360x691 under fantasy-ornate: 28px of
  overlap, the director's photograph to the pixel);
* **the anchor point** misses that one too, and already failed once on a padded
  left column's start edge.

Every one of them is a guess about the WIDTH OF THE CONTENT, and the content's
width is a thing the composition MEASURES.

**And it is a FIXED POINT rather than a latch.** The decision is taken once, from
the richest forms, and never re-asked. That is what makes it stable: giving way
shrinks the lane's budget, the budget steps a region down to a narrower form, the
narrower form no longer reaches the chrome — and a rule that re-asked would put
the richer form back, which is the 2-cycle the consumer's monotone latch existed
to bound. Inside one `resolve` the lane rects and the exclusion are in scope at
the same moment, so there is no loop to bound and nothing to keep in sync.

It reads the richest forms rather than the settled tree, which is STRICTLY MORE
CONSERVATIVE than the sampled version it replaces: a lane whose content reaches
the chrome at any rung gives way. A reservation should err in that direction.

### 5. A host that has said where its chrome is gets the platform's own row

`reserve` — the whole top inset — is a BOUNDING BOX on a host with a persistent
chrome row of its own, because that is all such a host has said. Reserving it in
every lane is the defect ADR-0027 exists to remove.

A composition that declares `exclusions` AND is riding the strip has said where
its chrome is, per column, so the lanes start at the platform's OWN row and the
declared rects push down only the lanes whose content meets them. Declaring
nothing keeps the bounding box, byte for byte. A composition not riding the strip
owes the platform's whole row whatever else it has declared.

### 6. Where the window→box conversion lives

`arrange` is the only pass that knows where a composition is, so it is the one
that converts. `measure` has no position and falls back to the surface's content
origin — exact for the full-bleed case every band-riding surface is (both passes
then produce the same cache key, so there is no second resolve), and conservative
otherwise: a composition placed lower measures against an origin above its own,
which over-states an exclusion's reach rather than under-stating it.

The origin joins the per-box cache key, and only when something reads it. Without
that an arrange whose box happened to equal the measure's would hand back the
measure-time resolution and the exclusions would silently not apply — a cache
returning an answer computed against a different ruler, which is the defect family
the solver keeps meeting.

## What is breaking, and what is not

**BREAKING, and it has an ADR-0040 row.**

* **B-24** — the `topbar` zone's geometry. A `topbar` region under
  `bandSafeContent` is laid into the free strip rather than across the
  composition's full width, and the lane band below it is floored at the
  platform's whole reservation. No SHIPPED surface moves through it today (the
  policy is new), which is exactly why the register's own B-18/B-21 precedent
  says a row is owed: `topbar` is shipped vocabulary, and the next reader tuning
  a row against the old full-width shape has no other way to learn it changed.

**NOT breaking.**

* `bandSafeContent` is a new enum value. A surface that does not ask for it is
  untouched — including by the gutter floor, which is scoped to this policy — and
  asking for it without declaring a `topbar` region resolves to what
  `deviceSafeContent` resolved to.
* A span row's slack going to its `fill` regions is inert everywhere it is not
  the band: until the band existed a span row was exactly as tall as its content,
  so there was never slack to give.
* `exclusions` is a new optional prop. A composition that declares none produces
  a byte-identical resolution and a byte-identical dump — pinned as the
  additivity case rather than asserted.
* `lanes[].exclusion` on the dump is 0 where it used to be absent, the same
  additive shape `collapsed` and `elided` already take.

## Consumers

The HUD demo (`examples/gallery/scenarios/hud.luau`) is the consumer of record:
~150 lines of hand-rolled policy, one `reachEpoch` token, one monotone latch,
three per-column reserve regions and two cluster-width spacers deleted, replaced
by one policy string and one declared prop. Its behaviour is preserved as the
specs above rather than as a comment — the fixture is what those specs drive.

**Rascal Rally's chip band moved with it (framework-gaps-phase2 ADOPT round,
2026-08-23), director-authorized.** `FacetSponsor/HudScreen.CHIP_PRESENT_OPTS
.rootPolicy` is `bandSafeContent` and `buildChipBand` places the row through one
`UI.Composition` with a `UI.Region{group="topbar"}` — the four hand-computed
Readables (`offsetX`, `offsetY`, `bandWidth`, `bandHeight`) this section used to
name as the hole §9 exists to remove are gone. Taking the cutover exposed a real
gap in §9 itself: a declared `topbar` region on a platform reporting no strip at
all was silently ZERO-WIDTH rather than the additive-safe full-width answer a
composition with no `topbar` region gets (`composition_resolve.localBand`'s
degenerate fallback, fixed alongside the cutover — `hasRealBand` in
`src/layout/composition.luau`, `tests/band_policy.spec.luau`'s own new case). The
device look is narrower now, not closed: `docs/handoff/G8G9-OWED-LIVE-WORK.md` §3
names exactly what is left (a measured 5px gap between the framework's generic
band-centre and the real engine pill's bottom-aligned anchor).

What DID move game-side in the same round is the other half of the audit's
consumer finding: `GearDockModel.placeInBand` and `HudZoneModel.sponsorTopStrip`
now read `platformChrome` instead of hand-deriving the topbar dock from
`GuiService.TopbarInset` with manual change-listeners.

## The alternatives, and why not

**A per-node `ignoresSafeArea`** (SwiftUI's split) was the shape the
parallel-sponsor ledger proposed for the same problem (`OWN-D38`). It is a bigger
vocabulary for a smaller answer: every node in the tree gains a question about
the safe area, and the one node that wanted it is a row the composition already
has a name for.

**Letting the consumer convert its own rects into the composition's box** would
have avoided the origin plumbing entirely — and it is exactly the geometry
feedback loop this decision exists to remove: a consumer cannot know where its
composition landed without sampling a solved rect.

**A fourth coverage fraction.** Three were measured wrong; a fourth is a fourth
guess about a width the framework measures.
