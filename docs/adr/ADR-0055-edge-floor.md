# ADR-0055 — `edgeFloor`: an opt-in padding knob, and `edgeToEdge` stays zero

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0055. Additive — no ADR-0040 row (no required-prop flip, no
documented-default change; see "What is deferred" below).
**Companions:** [ADR-0046](ADR-0046-band-safe-content-and-lane-exclusions.md)
(the `bandSafeContent` gutter floor this rides beside), [ADR-0027](ADR-0027-platform-chrome-band.md)
(why the top edge is exempt from every floor here).
**Home:** `src/render/renderer.luau` (`RendererAttachOpts.edgeFloor`, the
validation, the floor application in `solveAndApply`), `src/present/presenter.luau`
(`PresentOpts.edgeFloor`, threaded through `present`/`presentModal`/`presentCritical`).
**Guards:** `tests/edge_floor.spec.luau`.

## Context

Director ruling, 2026-08-23, on a rider to the FIX-2 device-pass round:

> If the user truly specifies edge-to-edge we should do so with no padding.
> Ensure the user can specify padding; perhaps even default so things don't
> ride the edge by default but can be made to.

Two separate asks, in order:

1. **A knob.** `rootPolicy = "coreSafeContent"`/`"deviceSafeContent"` already
   apply the platform's own safe-area insets, but nothing beyond that — a
   consumer who wants content to sit further off the glass than the platform
   strictly requires had no declared way to ask for it (short of hand-padding
   every screen's root child, which is exactly the kind of per-surface
   hand-roll ADR-0046 spent its own round removing). `bandSafeContent` is the
   one policy with an EXISTING floor (`themeMetrics.space.gutter`, ADR-0046
   §2) — everything else has none, by construction, not by measurement.
2. **A possible future default.** "Perhaps even default" — a floor that
   applies without a consumer asking. That is a product change (every example
   and every consumer screen moves a few pixels), and it is explicitly NOT
   this decision — see "What is deferred".

## Decision

### `edgeFloor: (number | string)?` — on `renderer.attach` and `PresentOpts`

A number (a literal pixel count, unscaled — the SAME number at every distance)
or a theme metric name (`themeSnapshot.resolveNumber`'s own grammar — the one
`UI.Table.cellPadding`, `anchor.gap`, `label.gap` already use), resolved
against the surface's own live, display-scaled metrics snapshot. A metric name
therefore rides the ten-foot ladder for free — `edgeFloor = "l"` is 1.5x
bigger at `displaySize = "Large"` than at a near distance, exactly as
`space.gutter` already is — while a literal number is not, because a literal
is a pixel count a caller chose on purpose and the ten-foot ladder exists to
scale THEME metrics, not arbitrary numbers a caller already decided.

**Floors bottom/left/right at `max(what the policy already reserves, this)`**
— never top (ADR-0027: the top edge is the platform's own row; a theme or
consumer value there would stop it sitting level with the engine's controls,
the one thing that ADR exists to protect, and every existing floor in this
codebase — `bandSafeContent`'s own gutter floor included — already carries the
same top exemption). Composes rather than replaces: a `bandSafeContent`
surface with a `space.gutter` of 8px and a declared `edgeFloor = 24` gets 24,
not 8 then 24 stacked, and a surface whose platform inset is already wider
than the requested floor is unaffected — the knob raises a floor, it never
lowers one the platform already set.

### The one refused combination: `edgeToEdge` + `edgeFloor`

**"If the user truly specifies edge-to-edge we should do so with no
padding."** `edgeToEdge` is the DECORATION policy (ADR-0046: *"a scrim or a
backdrop has to paint to the edges or it draws a rectangle inside the screen
with the world showing around it"*) — padding it contradicts the one thing it
exists to declare. Rather than silently ignoring `edgeFloor` on such a surface
(the exact "a policy string nothing consumes" shape ADR-0046 itself names as a
defect class it will not repeat), `renderer.attach` refuses the combination
at the call site:

```
Facet renderer: edgeFloor has no effect under rootPolicy = 'edgeToEdge'
(edge-to-edge is zero padding by definition) — drop edgeFloor, or use a
rootPolicy that reserves content insets.
```

**The pin the ruling asked for directly**: `rootPolicy = "edgeToEdge"` with no
`edgeFloor` opt at all resolves to exactly zero padding, byte for byte —
unchanged from before this decision, guarded by
`tests/edge_floor.spec.luau`'s first case rather than left to the general
"edgeToEdge paints under the insets" coverage `tests/renderer.spec.luau`
already carries.

### Shape, and why it rides `rootPolicy`'s own grammar rather than inventing one

The brief's own instruction: *"shape it per the existing rootPolicy/present
options grammar."* `renderer.attach`'s `opts` table is a closed key set
(`specGuard.assertKnownKeys`) with one string-enum member (`rootPolicy`) that
already validates loudly and one settled precedent for "number or theme metric
name, resolved via `themeSnapshot.resolveNumber`" (`Table.cellPadding`,
`anchor.gap`, `label.gap`, `label.iconSize`/`textSize`). `edgeFloor` is that
second shape, added to the same closed key set, threaded through
`PresentOpts` the identical way `rootPolicy` already is (a bare passthrough at
the one `renderer.attach` call site `PresentOpts` actually reaches —
`presenter.luau`'s `makeHandle`, shared by `present`/`presentModal`/
`presentCritical`). No new vocabulary, no new resolution helper.

## What is deferred

**The default.** This decision ships the KNOB only. Whether
`coreSafeContent`/`deviceSafeContent` (or `bandSafeContent`'s own floor)
should apply a NON-ZERO edge floor by default — "things don't ride the edge by
default but can be made to" — is a separate call, explicitly reserved to the
director's own word per the FIX-4 brief ("DO NOT FLIP THE DEFAULT... a separate
ADR-0040 row on their word"). The corrected measurement this round produced
(scenario-break counts at a 1px and a 2px universal floor, `edgeToEdge`
surfaces exempt per this ADR's own §"the one refused combination") is reported
in `task-fix4-report.md` item 2 for that decision, not decided here. If a
default ever changes, it is a required-value flip on every policy but
`edgeToEdge` and needs its own ADR-0040 row plus the `tests/lib/public_shape.luau`/
`tests/api_surface.spec.luau` pin update, same as every other row in that
register.

**ADDENDUM 2026-08-27 (task CONN, from review-fix234 Finding 3, code side):**
the report cited above also claimed RR calls neither `renderer.attach` nor
passes `rootPolicy` anywhere in its own source — that premise is false and
must not carry into the default-flip round. Verified directly against the live
`games/RascalRally/code` repo: `src/client/FacetSponsor/OmenState.luau:458`
calls `Facet.renderer.attach(core, root, self._env, built.adapter, { rootPolicy
= "edgeToEdge" })` DIRECTLY (bypassing `presenter.present`/`presentModal`/
`presentCritical` entirely), and `rootPolicy` appears at 11 non-spec call sites
across `FacetSettingsGui.luau`, `HudScreen.luau`, `ResultsScreen.luau`,
`OmenState.luau`, `FacetSponsor/init.luau` and `ChipRow.luau`. None of the 11
passes `edgeFloor` today (re-verified: zero hits), which is why this round's
knob-only change needed no RR edit — but a future default-flip is a
required-value change on every policy but `edgeToEdge`, and **the round that
proposes it must re-evaluate every one of these 11 sites individually**,
starting with `OmenState.luau:458`'s `edgeToEdge` call (exempt from the floor
by this ADR's own refusal rule, so unaffected either way) and every
`coreSafeContent`/`deviceSafeContent`/`bandSafeContent` site among the
remaining ten. "RR doesn't consume this surface" is not a safe premise to
inherit from this document.

## What is breaking, and what is not

**NOT breaking.** `edgeFloor` is a new, optional opt. Every existing call to
`renderer.attach`/`presenter.present`/`presentModal`/`presentCritical` that
does not pass it is byte-identical to before this decision — pinned as the
"omitted = unchanged" case in `tests/edge_floor.spec.luau` rather than assumed.
No documented default changes; no ADR-0040 row.

## The alternative, and why not

**A per-node `UI.Screen{ padding = ... }` prop instead of a root-level opt.**
Rejected for the same reason ADR-0046 rejected a per-node `ignoresSafeArea`:
the thing being declared is a property of the SURFACE (how far its content
sits from the device edge), not of any one node in its tree, and `rootPolicy`
is already the established seam for "declare something about this surface's
relationship to the edge." A second vocabulary for the same relationship
would be the "a bigger vocabulary for a smaller answer" ADR-0046 already
named and refused.
