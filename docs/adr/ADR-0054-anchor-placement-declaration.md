# ADR-0054 — `Facet.layout.anchorPlacement`: a declaration, not a coordinate

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0054. 0040 is the unreleased-breaking-changes register; **this
decision adds no row there** and "Not a breaking change" below says why.
**Companions:** [ADR-0052](ADR-0052-node-facts-reactive-props-schema-family.md)
(gap 33's `layout.transformFootprint` — the sibling "a consumer hand-
transcribes math the framework already owns" precedent this decision follows
the exact shape of), `.superpowers/sdd/framework-gaps-phase2/gap-registry.md`
item 39, `.superpowers/sdd/framework-gaps-phase2/binding-context.md`,
`.superpowers/sdd/release-candidate-review/task-purity-audit.md:376-377` (the
audit line this item is filed under, bare, with no home and no consumer
site — this ADR is the fresh evidence gathering the registry's own row says
item 39 needs), `src/layout/anchor_placement.luau`, `src/init.luau`,
`src/input/drag_contract.luau`, `src/input/drag_registry.luau`,
`tests/anchored_surface.spec.luau`; game side:
`games/RascalRally/code/src/client/FacetSponsor/init.luau`,
`games/RascalRally/code/tests/facet_anchor_placement_contract.spec.luau`,
`games/RascalRally/code/tests/facet_sponsor_story.spec.luau` (A44-4).

## Context

The purity audit's "remaining 23, in brief" names item 39 in five words and
nothing else: *"`armStaging` as a declaration rather than a coordinate"*
(`task-purity-audit.md:376-377`). No file, no consumer site, no shape. The
gap-registry's own row (`gap-registry.md:89`) records that honestly — "Not
specified by audit" in both the Home and Shape columns — and defers to a
fresh census.

**The census (task W3-E).** `armStaging` is real, shipped, and NOT new:
`UI.draggable`'s `armStaging: (() -> { x, y }?)?` (`src/input/drag_contract
.luau:54`) has been live since the parallel-sponsor round (OWN-D27,
`artifacts/parallel-sponsor/responsibility-ledger.md:75`, ~2026-08-04) — more
than two weeks before the audit that still lists it as an open gap. In FORM it
was already a declaration and not a coordinate: `registry.arm` (`src/input
/drag_registry.luau:949`) calls the closure and springs the ghost to whatever
it returns, rather than a value captured once at construction — the whole
point being that an armed pickup can be re-asked every frame rather than
frozen at pickup time (`nil` for a frame keeps the current spot, per the
prop's own doc comment).

**Grepping both repos (all spellings, case-insensitive) for the one real
consumer** finds exactly one: RascalRally's `HandDock`/`FacetSponsor`, via
`armStaging = function(index) return function() return slotStagingPoint(index)
end end` (`FacetSponsor/init.luau:2011-2015`) and `PlayFlow.stagingPointOf =
slotStagingPoint` (`:1878`, the SAME resolved point feeding the M26 pull
line — amendment A44's "one staging truth, two readers"). Reading
`slotStagingPoint` (`:1836-1859` before this round) found the gap ONE LEVEL
DOWN from where the audit's five words point: the callback's BODY still
computed a raw coordinate by hand —

```lua
return {
  x = source.x + source.w / 2 - slot / 2,
  y = source.y - slot - STAGING_GAP_PX,
}
```

— "above the source, centred, gapped by N pixels" is a placement a reader has
to reconstruct from arithmetic rather than read off a declaration. And Facet
already has that declaration, framework-side: `src/layout/anchor_placement
.luau`'s `.solve(request)` is the exact `edge`/`align`/`gap` → `{x, y}` pure
decision three OTHER framework callers already share — `present/anchored
.luau`'s `presentAnchored`, `present/presenter.luau`'s disclosure plate, and
`controls/row_actions.luau`'s floating menu (`anchor_placement.luau`'s own
header names all three). It was never reachable outside `src/present/*` and
`src/controls/*`: not required by `src/init.luau`, not in the surface ledger,
not in `docs/reference/api.md`. RascalRally could not have called it if it had
wanted to — the gap is real, it is just one file removed from where the
audit's own five words point.

## Decision

**Publish `Facet.layout.anchorPlacement = anchor_placement.solve`,
unmodified**, alongside `layout.transformFootprint` (`src/init.luau`) — the
same move gap 33 made for a sibling case of a consumer hand-transcribing math
the framework already owns internally. No new function, no new shape: the
pure solver keeps its existing signature (`{ source, size, safe, edge?,
align?, gap?, tail?, tailInset?, overflow? } -> { x, y, w, h, edge, flipped,
shift, fits, tailX?, tailY?, tailSuppressed }`), documented in full in
`docs/reference/api.md`'s `presentAnchored` section already. Reachability is
proven the same way gap 33's was (`tests/anchored_surface.spec.luau`,
red-first: nil before the export, the function after, plus a reference-
identity check against `anchor_placement.solve` itself) — and, because this
gap has a real consumer where gap 33 did not, a second case proves the
DECLARATION reproduces the exact numbers RascalRally's hand-rolled formula
used to produce, at this game's own real constants (`cardSlot = 64`,
`STAGING_GAP_PX = 8`).

**Migrated the one real consumer.** `slotStagingPoint` now declares the
placement instead of computing it:

```lua
local placement = Facet.layout.anchorPlacement({
  source = source,
  size = { w = slot, h = slot },
  safe = self._env:get("viewportRect"):get(),
  edge = "top",
  align = "center",
  gap = STAGING_GAP_PX,
})
return { x = placement.x, y = placement.y }
```

Both readers (`armStaging` and `PlayFlow:heldOrigin`) get the change for
free — there is still exactly one staging truth, resolved once, now stated
as a placement instead of reconstructed as arithmetic. The slot-unmounted
fallback (an un-banked Showstopper falling back to the dock's own rect) is
UNCHANGED and stays in game code: it is a real business-logic decision about
WHICH rect to anchor against, not placement arithmetic, and the framework has
no way to know a card table's own Showstopper rule.

**`safe` is the raw viewport, not the presenter's `safeBox()`.** The
presenter computes a narrower safe box (viewport minus the max of core/device
safe insets minus a theme gutter, `src/present/presenter.luau:779-797`) for
anchored surfaces that must clear a notch or a home indicator — but that
function is a `local`, never attached to the returned `self`, so it is not
public API today and extending the public surface to reach it is a second,
separable decision this round does not need: `slotStagingPoint` never clamped
against anything before this round, and the dock it anchors against is
already laid out well inside the safe content area by the HUD's own
composition, so the raw viewport is a permissive, never-triggers-in-practice
backstop rather than a behavior change. Confirmed rather than assumed: the
pre-existing regression suite (`facet_sponsor_story.spec.luau`, 63 cases
including A44-1..A44-4 and A45-1..A45-3, the ones that exercise this exact
seam) passes identically before and after the migration.

## What was rejected

**Changing `armStaging`'s own contract to accept a placement table directly**
(e.g. `armStaging = { edge = "top", align = "center", gap = 8 }` in place of
the function). Rejected: the ONE real consumer's fallback logic (unmounted
slot → dock root) is conditional, per-frame, and game-specific — a static
declaration table has nowhere to carry it, and a table-shaped `armStaging`
that ALSO accepted an `of` path with a fallback chain would be reinventing,
inside the drag contract, a second copy of the general-purpose
`anchor_placement` seam this decision already publishes. The existing
`() -> {x, y}?` contract is not the gap (it has been an honest declaration
in FORM since 2026-08-04); the gap was that the framework gave the consumer
no DECLARATIVE way to fill that closure's body. Publishing the solver closes
that without touching a contract three other framework callers already
depend on.

**A brand-new, RascalRally-flavoured "anchor above a rect" helper.** Rejected
on the DRY grounds gap 33's ADR already established: a formula that exists
once, framework-side, and is independently reachable, beats a purpose-built
wrapper this game would be the only caller of. `anchor_placement.solve` is
already general (four placement rules, a flip, a shift, an optional tail) —
narrowing it to "just the top-centered case" for one consumer would be
throwing away the parts of the existing, proven solver a future caller (a
menu, a callout, a second game) will want.

**Exposing `presenter.safeBox()` as new public API in the same round.**
Considered, to give the migrated call site a true safe-area-aware box.
Rejected as scope the census does not justify: the ONE consumer this gap has
never clamped, is not near a screen edge in any shipped layout, and a second
public export widening `src/present/presenter.luau` (already the largest file
under `SOURCE_CAP_LEDGER.md`'s watch) is a separable decision for whichever
future consumer actually needs it — flagged here rather than silently
deferred.

## Not a breaking change (no ADR-0040 row)

`Facet.layout.anchorPlacement` is a new field on an existing namespace table
(`layout`), covered by that namespace's existing surface-ledger row (extended,
not reclassified) — the same shape gap 33's `transformFootprint` used and the
same reasoning ADR-0053 gives for `presenter.raise`/`APP_CHROME_PRIORITY`. No
required prop changed, no documented default moved, and the function's own
behavior is untouched — it is the same `anchor_placement.solve` three
framework callers already exercise, merely reachable from one more place.
RascalRally's `slotStagingPoint` migration is confirmed geometry-identical by
the pre-existing `facet_sponsor_story.spec.luau` suite (63/63, unchanged
before and after) and by the new arithmetic-equivalence proof
(`facet_anchor_placement_contract.spec.luau`).
