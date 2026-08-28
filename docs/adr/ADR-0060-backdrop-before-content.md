# ADR-0060 — Backdrop-before-content: alpha isolates to the fade's content group

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0060. Additive — no ADR-0040 row. No prop is renamed, no default
value changes, no existing construction changes behavior: a node that is
ALREADY the fade target (`node.props.canvasGroup == true`, every shipped
construction found) resolves to itself exactly as before. The new behavior
(alpha routes to a resolved DESCENDANT canvasGroup when the declared node is
not one itself) only ever turns a previously-REFUSED construction (a hard
`error()` from `assertFadeCapable`, since no canvasGroup existed to write
`GroupTransparency` to at all) into a working one — nothing that rendered
before renders differently now.
**Home:** `src/render/transitions.luau` (`resolveAlphaTarget`,
`collectCanvasGroups`, `collectBackdrops`, `transitions.findBackdropFindings`,
`transitions.backdropIssue`, `coordinator.findings()`).
**Guards:** `tests/backdrop_fade.spec.luau` (registered in `tests/run.luau`).

## Context

Director's goal-prompt item 10, verbatim: "More POPS: cartwheel
triangle-tap (`cartwheelNarrowPopOverlap.mov`), glade tap (`newpop.mov`). Find
the GENERAL framework-level fix for the pop class, not per-site patches — we
keep finding these one at a time." Mandate (b): "do pop bugs show up
headlessly at all? Design the fundamental guard... Ship it as a gate, not a
one-off script."

**The repro (`newpop.mov`).** Tapping a Glade "Recent visitors" row fades a
detail card in OVER the list — mid-fade both the card's own text and the list
behind it are legible; it settles clean a beat later.

**Root cause, measured headlessly, zero frame-diff.** `examples/reference/
p1_glade/ui/shop.luau`'s `sheet()` helper — shared by all four of Glade's
pushed modals (nectar picker, provision shop, Keeper's Charm, wisp info), plus
two more in `keeper.luau` (the edit form, the Fresh Start confirm) — built
every modal as ONE `UI.ZStack{ canvasGroup = true }` wrapping BOTH an opaque
plate (`surface = "raised"`) and its content. `src/present/presenter.luau`'s
`presentModal` targets exactly that node for the push transition
(`{ enter = "materialize", class = "container" }`, which fades per
`schema.TRANSITION_FADES`). Driving it headlessly through `tests/lib/
fake_target` and reading `canvasGroupInstance.groupTransparency` directly (no
timing assumption, no frame-diff — the adapter's own recorded engine write)
across a 30-tick materialize:

| tick | `GroupTransparency` |
|---|---|
| 0 (seeded) | 1 |
| 3 | 0.727 |
| 9 | 0.234 |
| 29 (settled) | 0.003 |

The PLATE (`Panel`, `surface = "raised"`) is a child of that SAME node, so its
own paint rides the identical number — at every tick above, the plate is
exactly as translucent as its text. `CanvasGroup.GroupTransparency` is one
engine scalar Roblox composites over the WHOLE rendered subtree; there is no
way to declare "this child stays opaque" from inside it. "The backdrop is
legible no later than the content" (the director's own candidate invariant)
was IMPOSSIBLE BY CONSTRUCTION for any modal built this way — not a timing
bug, a shape bug.

**Why this recurred (the "one at a time" complaint, explained).** `shop.sheet`'s
own header comment, before this task, read: *"a modal's body: the presenter's
fading surface transition targets the root's single declared canvasGroup
child, so every modal in this proof has exactly one."* That sentence is
correct and is exactly the trap: the framework's own working example taught
"wrap the whole modal in one canvasGroup," and nothing enforced that the
OPAQUE part had to be outside it. Six sites in one reference app alone shared
this exact shape by copying the pattern forward.

## Decision

**Split the write, not the transition.** A transition still targets ONE
declared node (`presenter.luau`'s existing "root or single direct-child
canvasGroup" resolution is UNCHANGED — this ADR does not touch it). What
changes is which node the COORDINATOR (`src/render/transitions.luau`)
actually writes `GroupTransparency` to:

- **Position/scale** (`controller.setPresentationTransform`) still target the
  DECLARED node, exactly as before. A plain `UIScale`/offset moves a plate and
  its content as one rigid unit whether or not that node is a canvasGroup —
  `materialize` still reads as the whole card growing in.
- **Alpha** (`controller.setPresentationTransparency`) targets a RESOLVED
  node: if the declared node already has `canvasGroup = true`, it is the
  target (today's construction, unchanged — every shipped fade before this
  task takes this branch). Otherwise, `resolveAlphaTarget` searches the
  declared node's subtree for the ONE `canvasGroup = true` descendant
  (stopping descent at each one found, so a nested INDEPENDENT fade group — a
  chip's own `fade` — is never crossed into) and routes `GroupTransparency`
  there. Zero or more than one candidate falls back to the declared node
  itself, so `assertFadeCapable`'s existing refusal still fires exactly as it
  always has for those cases.

This makes "plate outside, content-only canvasGroup one level in" a
CONSTRUCTION THAT WORKS, for the first time, without widening the transition
API surface at all — no new prop, no new option. An author fixes the class by
moving one node.

**The mandate-(b) guard is structural, not temporal.** `transitions.
findBackdropFindings(alphaPath, alphaNode)` answers "does the node that will
actually fade still compose an opaque backdrop as one of its own DIRECT
children" — a pure read of `.props`/`.children`, no clock, no engine, no
adapter. **"Opaque backdrop" is a class, not a hand-list of one prop
(fix round 1, review finding 2):** the same question is asked of Facet's TWO
paint channels — an authored `surface` (any role but `plain`) and a `Box`'s
own `tint` (unless its `transparency` is a literal `1`, fully invisible) —
because both write the SAME engine property, `BackgroundColor3`. `tint` is
NOT flagged on any other class: `Text`/`Image`/`Path`/`Stage` all accept
`tint` too, but there it colours a glyph, a picture, a stroke or a clear-
colour, never a background rect a sibling could hide behind — `paintsBackdrop`
checks the node's CLASS before its paint, not just its props, so a `UI.Text{
tint = … }` label is never mistaken for a plate. Deliberately ONE LEVEL: a
backdrop paint two levels into the content is ordinary content a shallower
plate already made opaque, not a second backdrop, and flagging it would bury
the real finding in noise (measured: the un-narrowed version reported
`Portrait`/`Favourite` as false positives inside an already-fixed `Panel`).
Every coordinator accumulates every finding it ever sees through a real
`beginEnter`/`shouldRetire`, exposed as `coordinator.findings()` (a copy, like
`controller.stats()`) — so a regression reddens the moment its push
transition first runs, in a test or in Studio, with nothing to remember to
re-run. **Also fix round 1: the record only fires when the transition
actually fades** (`fades(spec, form)`) — a pure slide writes no
`GroupTransparency` anywhere, so a backdrop check against it was checking a
property nothing ever animates (measured: RascalRally's `HandDock`-adjacent
`BuyBar`, a `{enter = "slide-up"}` with no fade, flagged its own `Buy` button
as an "opaque backdrop" — true of the shape, meaningless for the bug). This
was the ONE false positive found across two reference apps and RascalRally's
whole FacetSponsor surface this round; narrowing to fading transitions only
removed it, with zero loss of real coverage (every genuine finding this round
was already on a fading transition).

**The self-case is DETECTED, not automatically REPAIRED (fix round 1, review
finding 3).** `resolveAlphaTarget` returns the declared node unchanged
whenever it is ALREADY `canvasGroup = true` (the self-case) — on the
reasoning that an author who wrote that meant to fade exactly that node.
`findBackdropFindings` takes no shortcut for this case: it reads whatever
node `resolveAlphaTarget` hands it, self-case or resolved, identically —
proven directly in `tests/backdrop_fade.spec.luau`'s own self-case test, and
proven the hard way by a RED-TEAM review that fed `MessageLayer.ribbon()`'s
UNMODIFIED, self-case `HostRibbon`/`RibbonPlate` straight into this finder
and got exactly one finding back. What the resolver does NOT do is repair a
flagged self-case for you: there is no OTHER node to redirect
`GroupTransparency` to when the plate and the declared fade target are the
SAME node's own children, so a flagged self-case still needs the identical
blueprint surgery every other finding does (the plate moves to a sibling, its
former content moves one level in, under a NEW canvasGroup). **This report's
own earlier framing — "why this kills the CLASS, not one site" — invited
exactly this over-reading; stated plainly, once, here: a change that makes a
CORRECT construction possible does not retroactively repair an
already-broken one, self-case or not. The finder would have found every real
finding fixed this round on the day ADR-0060 landed, had it been pointed at
them; mandate (b)'s own instrument was always capable, the round-0 sweep just
never ran it wide enough to say so.**

**What this answers about mandate (b), precisely.** This whole class is
visible with ZERO frames stepped: the defect is a STATIC fact about the
blueprint tree (a `surface`-painting direct child of a fade group), true the
instant the tree is built, before any `clock:step` at all. It does NOT need a
frame-diff or an engine — which is stronger than "headlessly visible," it is
"visible at declaration time." What it does NOT catch: FIX-3's cause A (slide
distance) and cause B (`TabView` content halving) are unrelated mechanisms —
this guard is scoped to the fade/backdrop family only, honestly, not a
universal pop detector.

## Alternatives considered

- **A first-paint-equals-settled-layout invariant** (the director's other
  named candidate). Investigated against `cartwheelNarrowPopOverlap.mov`'s
  Brews-screen overlap (task-pop-report.md's cartwheel section): headless
  measurement found the broken layout is STABLE — identical between the
  first `presenter.refresh()` and every subsequent one, at every width tried.
  There is no "first frame differs from settled" moment to catch; the
  overlap is an at-rest `ViewThatFits`-vs-`fill`-sibling measurement
  interaction (director ruling 2026-08-14, "a candidate is judged at its
  ideal size, not the size it could be squeezed into" — deliberate,
  documented layout behavior, not a framework defect), not a pop. This
  invariant remains worth building for a genuinely transient class if one
  is found; it answers nothing about either video in this round, so it is
  not shipped here (see task-pop-report.md for the honest accounting).
- **A hard runtime refusal** (extend `assertFadeCapable` to error whenever a
  fade group composes a direct opaque child, no escape hatch). Rejected for
  THIS round: the blast radius across five reference apps' many `canvasGroup
  = true` sites was not fully audited, and a refusal that fires in shipped
  Studio sessions (not just tests) risks breaking constructions this task
  did not review. The GATE (`coordinator.findings()` + the registered spec)
  gets the same "reddens on the exact defect" property without the
  live-runtime risk; a future round can promote it to a refusal once the
  wider sweep (mandate a) has audited the rest of the tree.
- **Wrapping the plate in its OWN second `canvasGroup`, nested inside the
  first, with an independent (front-loaded) alpha curve.** Rejected:
  `GroupTransparency` COMPOUNDS on nested `CanvasGroup`s (the outer's alpha
  still multiplies the inner's render), so a plate inside a nested group
  would be MORE transparent overall, not less — this does not solve the
  problem, it relocates it. The plate has to be a SIBLING, outside the
  fading node entirely, which is what the shipped fix requires.

## Consequences

- `examples/reference/p1_glade/ui/shop.luau` (`sheet()`, `page()` — new,
  shared — `shop.wisp`, the charm tiers) and `ui/keeper.luau` (`editForm`,
  `confirmReset`) were restructured to the plate-outside shape; `shop.sheet`
  itself no longer declares `canvasGroup` (it is a plain positioning
  `ZStack` now — see its own header comment for the full account).
- `tests/reference/glade_spec.luau`'s one path-coupled assertion
  (`/Panel/Seen`) was updated to the new depth (`/PanelBody/Seen`); no
  assertion's INTENT changed, only the path a restructured tree produces it
  at.
- Two structural regressions this task's OWN restructuring introduced
  (`keeper.editForm`, `keeper.confirmReset` — each built its own copy of the
  now-fixed shape) were caught by the full targeted suite before landing,
  not shipped; both now share `shop.page`/the plate-split pattern rather
  than carrying a third copy.
- **RascalRally, round 0 vs. fix round 1 (corrected).** Round 0's report
  claimed every `FacetSponsor` `canvasGroup` site was a self-case needing no
  RR-side migration — TRUE of `resolveAlphaTarget`'s own resolution (spot-
  checked, accurate), but that is a DIFFERENT question from "does any of them
  compose the newpop.mov shape," which round 0 never actually ran the finder
  to answer. A RED-TEAM review (fix round 1) fed `MessageLayer.ribbon()`'s
  unmodified `HostRibbon`/`RibbonPlate` into `findBackdropFindings` directly
  and got a finding back — the exact bug, live in production. Fix round 1's
  own sweep (`games/RascalRally/code/tests/facet_sponsor_backdrop_sweep.spec.
  luau`, registered) then found and fixed SEVEN real instances of this shape
  across the game's own FacetSponsor surfaces — `MessageLayer.ribbon`
  (`HostRibbon`/`RibbonPlate`), `StartCountdown` (`CountdownScrim`, a
  `tint`-painted plate — invisible to round 0's `surface`-only detector),
  `Ticker` (`EntryPlate`, also `tint`), `TableScreen` (`TablePlate`, also
  `tint` — the main driver table), `RolePickScreen` (`Scrim` AND `Card`, the
  mandatory join modal), `ResultsScreen`'s `Payoff` piece, and `HudScreen`'s
  dead-code table placeholder — each restructured with the SAME plate-
  outside/content-in-a-new-inner-group shape this ADR's own fix uses, no new
  API. `ResultsScreen`'s main `ResultsRoot`/`ResultsScrim` (the full-screen
  results dimmer) is a CONFIRMED, real eighth instance, root-caused and
  fix-specified but NOT executed this round — its `focusGroups`/
  `adjustTargets` machinery threads absolute paths through the exact subtree
  the fix would restructure, and the file is large and heavily relied upon;
  deferred deliberately (task-pop-report.md's fix-round-1 section), the same
  honest-deferral standard round 0 set for the cartwheel toolbar overlap.
  Every fix landed here also needed the SAME thing Glade's did: the site's
  own PATH constants updated for the new nesting depth (RR's `MessageLayer.
  PATHS`, `StartCountdown.PATHS`, `Ticker.entryPath`, `TableScreen.PATHS`,
  `RolePickScreen.PATHS`) and every consumer of those constants (RR's own
  test suite) migrated in the SAME commit set — recorded here per the root
  `CLAUDE.md`'s consumer-lockstep rule, not asserted without the RR-side
  evidence to back it (RR suite: 3537 passed, 1 pre-existing unrelated
  failure, task-pop-report.md's fix-round-1 tail).
