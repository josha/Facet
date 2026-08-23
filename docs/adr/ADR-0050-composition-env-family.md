# ADR-0050 — The composition/env family (framework-gaps-phase2, wave 3-A)

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0050. 0049 is content-terms height. This decision touches NO row in
the ADR-0040 register: every surface below is additive (a new sibling
`ARRANGEMENTS` preset, two new dump/resolution fields, two new published
constants) — nothing flips to required and no documented default changes
value. See "What is breaking, and what is not".
**Companions:** [ADR-0046](ADR-0046-band-safe-content-and-lane-exclusions.md)
(`platformChrome`, `bandSafeContent`, `exclusions` — the mechanism three of
this round's nine items turned out to already be), [ADR-0023](ADR-0023-declared-content-composition.md)
(the composition vocabulary `leadFirst` and `simplified` extend),
[ADR-0014] (cited in `src/present/presenter.luau`'s own responder-priority
section — the live authority `interactionTokens.contextPriority` mirrors),
`.superpowers/sdd/framework-gaps-phase2/task-w3a-brief.md` / `gap-registry.md`
(the mission).
**Home:** `src/layout/composition.luau` (`ARRANGEMENTS.leadFirst`,
`Resolution.simplified`, `composition.dump`), `src/controls/virtual_grid.luau`
(`dump().crossExtent`/`.laneWidth`), `src/input/interaction_tokens.luau`
(`contextPriority`), `src/init.luau` (`EXIT_CAP_SECONDS`).
**Guards:** `tests/composition.spec.luau` (`leadFirst`, four cases),
`tests/elision_recovery.spec.luau` (`simplified`, six cases),
`tests/virtual_grid.spec.luau` + `tests/virtual_hgrid.spec.luau`
(`crossExtent`/`laneWidth`, four cases across both axes), `tests/interaction_tokens.spec.luau`
(`contextPriority`, three cases incl. a source-text drift pin against
`presenter.luau`'s own literals), `tests/transitions.spec.luau` (`Facet.EXIT_CAP_SECONDS`
pinned equal to the internal authority). RR: `tests/input_authority.spec.luau`
(`FACET_BASE_SCREEN_PRIORITY` pinned against the live Facet export),
`tests/facet_sponsor_presenter_lifecycle.spec.luau` (`destroy()`, exercising
the `EXIT_CAP_SECONDS` migration end to end).

## Context

`gap-registry.md`'s composition/env family, nine in-brief items (12, 25, 26,
27, 28, 30, 35, 36, 41), assigned one round. Five of the nine (25, 26, 30, 35,
36) were framed as a **census**: several of them post-date waves 1–2's own
gap 8/9 fix (`platformChrome`, `bandSafeContent`, per-lane `exclusions`),
which the audit had not seen when it was written, so the brief's own
instruction was "prove, never assume" rather than take the audit's 2026-08-21
description as still current. Four (12, 27, 28, 41) were framed as small,
audit-named builds, with the brief's own escape hatch: dispose with
measurement if the audit over-reached.

## Decision

### Census half — three DISSOLVE, one DISPOSE, one BUILD

**Item 36 (`platformChrome` as a rect, not only insets) — DISSOLVES.**
`src/env/environment.luau:404-557`'s `platformChrome` memo already returns
`{ band, rects, insets, bandInsets }`: `band` is a window-space rect, `rects`
is a LIST of them (the platform's own controls, plus — since gap 8/9 — any
app-declared chrome merged in). This is not merely "a rect available on
request"; it is consumed live today: `composition_resolve.luau:382-393`
converts `platformChrome.rects`-shaped exclusions into the composition's own
box, `renderer.luau:1761-1767` reads `.band`/`.bandInsets` under
`bandSafeContent`, and `examples/gallery/scenarios/hud.luau` exercises all
four fields end to end (`platformChrome.band`/`.bandInsets`/`.insets`,
extensively — see its own `§9`-tagged comments). RascalRally's
`GearDockModel.placeInBand` reads `platformChrome.band` directly, with its own
header stating the fact it replaced ("three raw engine reads and three manual
connections"). Nothing to build; the item's own worry (a consumer stuck with
only insets) was resolved by gap 8/9, before this round opened.

**Item 30 (a derived `effectiveSafeInsets` fact) — DISSOLVES.**
`renderer.luau:1849-1865` computes exactly the three-way combination the
registry's own "BUILT would look like" describes — platform chrome
(`bandInsets`/`deviceSafeInsets`) + the theme's own gutter floor
(`space.gutter`, ADR-0046 §2) + the per-policy ten-foot overscan adjustment —
under `rootPolicy = "bandSafeContent"`, pinned by
`tests/band_policy.spec.luau:139-193` ("`bandSafeContent` floors its other
three edges at the theme's own gutter"). It is **not** published as a
standalone `Readable` a consumer subscribes to — it is applied automatically
to every surface presented under that policy, which `hud.luau:575-604`'s own
before/after commentary documents as the *stronger* fix: a ~150-line hand-roll
(a `margin` spending `platformChrome.bandInsets` by hand, a `screenPadding`
flooring each edge against the theme gutter, a `reachEpoch` convergence latch)
collapsed to one declared policy plus one prop. Per the simplicity ladder, a
value applied automatically by the policy a surface already declares is a
better answer than a second Readable the surface would have to remember to
read — no consumer, in Facet's own examples or in RascalRally, hand-derives an
"effective" safe inset today (grepped; none found), so there is no live pain a
new export would relieve.

**Item 35 (a topbar band occupancy claim) — DISSOLVES.**
The mechanism the item asks for — "one game surface can tell another it is
already sitting there" — is `appChromeRects` → `platformChrome.rects`/`.band`
(`environment.luau:472-514`): any surface declares the rect it occupies, and
`platformChrome` merges it into the SAME occupancy list the platform's own
controls populate, narrowing `.band` for whoever reads it next — proven live
in `tests/hud_chrome_rotation.spec.luau` (`env:set("appChromeRects", …)`,
asserted against the composition/topbar-band response) and in
`hud.luau`'s chip row. RascalRally's own `GearDockModel`/`HudZoneModel` pair
(cited by the registry as this item's consumer) do NOT use this mechanism for
their gear-vs-chip coordination — and correctly not: both are the SAME app's
own pure modules (`HudZoneModel.sponsorTopStrip` calls
`GearDockModel.gearRightEdge` directly, a one-line same-codebase call), which
is the simplicity ladder's own answer for two co-owned surfaces and would gain
nothing from routing through a framework claim registry built for genuinely
decoupled composables. `GearDockModel`'s own header confirms the PLATFORM half
of this item's premise (manual `TopbarInset` listeners) was already replaced
by `platformChrome.band` in an earlier round. Nothing here is unbuilt; the
audit's own citation (`sponsorTopStrip`/`GearDockModel` "hand-deriving topbar
docking … with manual change-listeners") is gap 9's finding, fixed by gap 9,
not a residue this item still owns.

**Item 25 (`VirtualGrid` has no measured line-extent mode) — DISPOSED, measured.**
The census question the brief poses — "does crossExtent/`\"auto\"` (G4) answer
it?" — is **no**: `viewportExtent = "auto"` (G4) self-measures the SCROLL axis
(a different fact, already shipped on `VirtualGrid` too — `virtual_grid.luau:436-457`)
and `VirtualList.crossExtent = "measured"` self-measures the CROSS axis of a
LIST — neither is `itemExtent`, the LINE extent this item actually names.
`VirtualList.itemExtent = "measured"` (Stage 2, 2026-08-15) is real and does
what this item wants for a list; `VirtualGrid.itemExtent` has no such form
today — genuinely open, not answered by G4. Disposed anyway, on measurement:
grepped every `VirtualGrid`/`newVirtualGrid` construction site in this repo
and in RascalRally (thirteen files, `tests/collection_self_measure.spec.luau`
through the RR contract specs) — **zero** hand-measure a line extent. Every
site either hands a fixed number or an author-computed per-line function
(`itemExtent = function(line, use) …`, already the closed-form escape hatch
for "I know the formula"). `VirtualGrid`'s own header already documents the
same refuse-without-a-consumer precedent for a materially similar ask
(`minColumnWidth`, `virtual_grid.luau:203-210`: "a route rather than a
shrug"), and a measured LINE (as opposed to a measured ITEM) is a harder
design question with no consumer to arbitrate it: a list's row IS its item, so
"measured" means one thing; a grid's line holds `columns` cells, so
"measured" would have to decide whose height governs the line — tallest?
declared lane? — a decision this round has no driving use case to make
honestly. Booked as an owed follow-up, not silently declined; the shape is a
genuine design question for whenever a consumer needs it.

**Item 26 (`VirtualGrid.dump()` hides the per-lane cross extent) — BUILT.**
`dump()` now reports `crossExtent` (the mounted band's own solved box on the
grid's cross axis) and `laneWidth` (`floor((crossExtent − gap × (lanes − 1)) /
lanes)`, clamped at 0 — the SAME formula the control's own header already
names as executing for the mounted `UI.Grid` band). Captured in `syncGeometry`
unconditionally (there is no spec key to gate it behind, unlike
`viewportExtent = "auto"`): the presenter already calls `syncGeometry` on
every refresh for any contribution that declares it, so this costs nothing
new to wire, only a second field on the box it was already reading.
`tests/virtual_grid.spec.luau` pins the vertical axis (differential against
the same fixture the shipped column-arithmetic case already uses) and a
clamp-at-zero edge case; `tests/virtual_hgrid.spec.luau` pins the sideways
axis (the cross axis transposes to the height, matching the control's own
axis-transpose table).

### Build half — one BUILT, one BUILT, one DISPOSE

**Item 12 (`ARRANGEMENTS` has no lead-first two-lane preset) — BUILT.**
`composition.ARRANGEMENTS.leadFirst = { lead } { main, trail }`, the mirror
of the shipped `twoLane` (`{ main } { lead, trail }`). Census: grepped every
custom two-lane arrangement in the reference apps — six re-authorings across
two apps, not three as the audit's own imprecise count states (the registry's
own header already flags this class of audit miscount): four identical sites
in `p2_cartwheel` (`shell.luau`, `dashboard.luau` ×2, `workbench.luau`), each
declaring `{ name = "twoLane", lanes = { { "lead" }, { "main" } } }` — the
exact shape `leadFirst` now ships, and the exact **shadow** the audit names
(a custom arrangement reusing the built-in preset's own name for different
lanes, so a dump could not tell the two apart); and two sites in
`p5_wardrobe` (`split`/`stacked`, `main`/`trail` only, no `lead` affinity at
all, plus a fallback-collapse-to-one-lane shape `leadFirst` does not cover).
**Swept: the four shadowing sites**, which is where the name-collision the
audit calls out actually lived. **Not swept: the two `p5_wardrobe` sites** —
a different lane vocabulary (no `lead` affinity) and a different shape (an
explicit stacked-fallback second arrangement), not the "lead-first two-lane"
this item names; converting them would be manufacturing a fit rather than
reporting one. `tests/composition.spec.luau` pins the preset's shape, that
`twoLane` is unchanged (additive, not a rewrite), a resolve through the real
name, and that the built-in-name list in the refusal error includes it.

**Item 28 (`resolution.simplified` beside `unshown`) — BUILT.**
`Resolution.simplified` / `composition.dump().simplified`: one entry per
ON-SCREEN region whose `activeForm > 1` (dropped regions are `activeForm = 0`
and never appear), built in the SAME per-region walk `unshown` already makes.
Answers a genuinely different question than `unshown` — "is this screen
simplified" vs. "is this screen missing something" — with an
overlapping-but-unequal answer set (a `recover = "none"` region is
`simplified` and never `unshown`). Real, live consumer found and migrated:
`examples/gallery/scenarios/hud.luau`'s overflow panel used to answer "is
anything simplified" by looping every region and checking `row.activeForm >
1` by hand (its own comment named the two facts as "the census reads both
halves of the same dump"); `tests/elision_recovery.spec.luau` pins the new
field against that same fixture, invariant-style (computed independently from
`regionById` in the test, not a hardcoded literal), plus the dropped-never-
appears rule, the per-entry `form`, the empty-when-nothing-stepped-down
additivity, and dump-order parity. RascalRally's `ResultsScreen.luau` (the
registry's own cited `unshown` consumer) does not hand-derive a simplified
count — a genuine clean negative, not a missed site.

**Item 27 (`composition.minimumOffer`) — DISPOSED, measured.**
The audit names this bare, with its own admission that "shape undetermined by
the audit — this needs a design pass before implementation, not just a
mechanical fix." Measured: zero consumer sites in Facet's examples/tests or in
RascalRally reference or use anything named `minimumOffer`/`minOffer`, and
`composition.resolve` is already the PURE, headlessly-sweepable entry point
the module's own header advertises — a consumer that wants "the smallest
offer this declaration still resolves legally at" can already answer that by
sweeping candidate offers against the public `resolve()` and reading
`resolution.fallback`/`.legal`, with no new framework surface. Building an
API whose shape the audit itself could not state, against zero measured pain,
and where the underlying capability is already reachable in a few lines
against the existing pure entry point, fails the simplicity ladder's own
first rung ("exists at all?"). Booked as an owed design-pass item, not
silently declined — a real consumer with a real shape in mind is the trigger
to revisit it.

### Item 41 (`Facet.EXIT_CAP_SECONDS` + `interactionTokens.contextPriority`) — BUILT

Both constants the audit names, published as real exports, with the RR
consumer sites the audit's own framing predicts actually found and migrated:

- **`Facet.EXIT_CAP_SECONDS`** (`src/init.luau`, reading
  `src/render/transitions.luau`'s existing internal `EXIT_CAP_SECONDS`).
  RascalRally's `FacetSponsor/init.luau:114-117` carried a local
  `EXIT_CAP_S = 0.5` whose own comment cited "docs/reference/api.md §
  Structural transitions" as its source — copied prose, exactly the audit's
  shape. Migrated: `new()` now reads `self._exitCapSeconds =
  Facet.EXIT_CAP_SECONDS` (Facet is already resolved by that point in
  construction on every path, injected or lazy), and `destroy()`'s own final
  `tick` spends `self._exitCapSeconds` instead of the module literal.
  `tests/transitions.spec.luau` pins `Facet.EXIT_CAP_SECONDS` equal to the
  internal authority; RR's `facet_sponsor_presenter_lifecycle.spec.luau`
  exercises `destroy()` end to end.
- **`interactionTokens.contextPriority`** (`src/input/interaction_tokens.luau`):
  `{ baseScreen = 1500, engagedBase = 3000, modalStep = 500 }`, mirroring
  `presenter.luau`'s own ADR-0014 responder-priority locals
  (`BASE_SCREEN_PRIORITY`, `ENGAGED_BASE_PRIORITY`, the `+ 500` modal step).
  RascalRally's `InputActions.luau:87-90` carried `FACET_BASE_SCREEN_PRIORITY
  = 1500` with a comment citing `presenter.luau:579` as its source (its own
  words: "spelled here so the rule is a number a test can assert, not a
  sentence in a comment") — the audit's grouped item, found live. Migrated:
  `tests/input_authority.spec.luau` gained a drift-pin,
  `InputActions.FACET_BASE_SCREEN_PRIORITY == Facet.interactionTokens.contextPriority.baseScreen`,
  so a future change to either side fails loud instead of re-opening DF-1's
  arbitration bug one layer up. Two framework comment sites that used to cite
  "presenter.luau's own `contextPriority` comment" in prose
  (`src/input/contribution.luau:188-190`, `src/controls/row_actions.luau:1687-1693`)
  now point at the real export.

**`presenter.luau` itself is untouched — a deliberate lane boundary, not an
oversight.** This round's brief scopes `src/present/*` OUT (a separate
"presenter-seam family" round owns it); `presenter.luau`'s own
`BASE_SCREEN_PRIORITY`/`ENGAGED_BASE_PRIORITY`/`+500` stay local literals,
duplicated rather than reading `interactionTokens.contextPriority`. The two
copies cannot drift silently: `tests/interaction_tokens.spec.luau` greps
`presenter.luau`'s source text for the exact literals and fails if they ever
diverge from the published token. Wiring `presenter.luau` to read the token
directly — closing the duplication rather than merely detecting it — is
booked as a Studio-owed follow-up for whichever round next opens
`src/present/*`.

## What is NOT built (and why each is a real boundary, not a shortcut)

**No RR migration for items 12/26/28.** Grepped for consumer sites in
`games/RascalRally/code`: `leadFirst` — RR's `ResultsScreen.luau` uses the
built-in `threeLane`/`twoLane`/`column` by name, never a custom two-lane
re-authoring; `VirtualGrid.dump()` — RR never constructs a `VirtualGrid` at
all (only exercises Facet's own control contract in
`tests/facet_virtual_grid_contract.spec.luau`, which needed no change);
`resolution.simplified` — covered above. All three are genuine clean
negatives, not missed sites — RR's own suite (unchanged) is the evidence: a
purely additive field cannot break a consumer that never reads it, and it
did not.

**`presenter.luau`'s own literals are not sourced from the new token** (see
Item 41 above) — the lane boundary, not a technical obstacle.

## What is breaking, and what is not

**Nothing breaks.** Every surface in this round is additive: `ARRANGEMENTS`
gained a sibling entry (`twoLane`, `column`, `threeLane` are byte-identical —
pinned in `tests/composition.spec.luau`); `Resolution`/`composition.dump()`
gained two fields each (`simplified`, and `VirtualGrid.dump()`'s `crossExtent`/
`laneWidth`) that read `nil`/empty on any resolution built before this round
existed; `Facet.EXIT_CAP_SECONDS` and `interactionTokens.contextPriority` are
new root/namespace members, not changes to existing ones. No ADR-0040 row.

## Registry evidence

Per the round's own instruction: dissolve with demonstration, dispose with
measurement, or build — evidence first, never assumed from "same home file".

- **Item 12** — BUILT (§ above).
- **Item 25** — DISPOSED, measured (§ above). Owed: a measured-line-extent
  design pass, triggered by a real consumer.
- **Item 26** — BUILT (§ above).
- **Item 27** — DISPOSED, measured (§ above). Owed: a `minimumOffer` design
  pass, triggered by a real consumer with a stated shape.
- **Item 28** — BUILT (§ above).
- **Item 30** — DISSOLVED WITH DEMONSTRATION (§ above); already answered by
  gap 8/9's `bandSafeContent` gutter floor.
- **Item 35** — DISSOLVED WITH DEMONSTRATION (§ above); already answered by
  gap 8/9's `appChromeRects` → `platformChrome` merge.
- **Item 36** — DISSOLVED WITH DEMONSTRATION (§ above); already answered by
  gap 8/9's `platformChrome` shape.
- **Item 41** — BUILT, both halves, both with a live RR migration (§ above).

## Alternatives, and why not

**Fold `p5_wardrobe`'s `split`/`stacked` into `leadFirst` too**, to make item
12's "six re-authorings" collapse to zero rather than two. Rejected: those
two sites declare no `lead` affinity at all and rely on a second, fallback
arrangement (`stacked`) `leadFirst` has no equivalent for — converting them
would change their actual lane vocabulary to fit a preset shape that is not
theirs, which is the "manufacture churn to force a count" the campaign's own
binding context explicitly warns against. Recorded as a real, distinct
two-affinity/fallback shape the framework does not yet name, not silently
folded in.

**Wire `presenter.luau` to read `interactionTokens.contextPriority` in this
round anyway**, closing the duplication instead of only pinning it. Rejected:
out of lane (`src/present/*` is explicitly reserved for a later round in this
wave), and the source-text drift pin gives the same safety property (a
divergence fails loud) without reaching into a file this round was told to
leave alone.

**Publish `effectiveSafeInsets` as a new standalone `Readable` anyway**, to
literally match item 30's "BUILT would look like" wording even though nothing
needs it. Rejected: no consumer, live or historical, has ever hand-derived
this value independently of a `rootPolicy` solve — the ONE place that used to
(`hud.luau`, pre-gap-8/9) was fixed by deleting the hand-roll in favor of the
policy doing it automatically, which is the outcome a new export would
regress toward re-inventing. A speculative export with no reader is exactly
the "framework should own this floor" shape this campaign's own gap-3/gap-14
rounds warn against shipping ahead of a need.
