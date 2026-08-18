# ADR-0023 — Declared-content adaptive composition (`UI.Composition`), and the height half of `adaptive.conditions`

**Date:** 2026-07-31
**Status:** Accepted
**Stage:** `parallel-sponsor` (roadmap Step 6), ledger row **OWN-D45**
**Commissioned by:** director visual round 4, **DV4-3** (verbatim): *"this also seems like exactly
the type of thing facet should solve well — we have a screen with information we declare, and want
to ensure the ui auto-adapts well everywhere."*
**Companions:** `artifacts/parallel-sponsor/responsibility-ledger.md` (OWN-D45),
`games/RascalRally/docs/ui/UI_SPEC_sponsor_facet.md` §S16.2–§S16.7 (the designer-seat contract this
implements), ADR-0011 (semver), ADR-0019 (theme snapshot / metric names), ADR-0022 (motion,
transitions, paint escapes).

## Context

Facet had two adaptive primitives and a hole between them.

- **`UI.AdaptiveStack`** resolves ONE axis, from a bound `Readable`. The author decides the axis.
- **`UI.ViewThatFits`** resolves ONE container's candidate, by measuring it against the space that
  container actually received.
- **`adaptive.conditions`** classifies the **viewport width** and nothing else.

Neither answers the screen-level question: *"here is everything this surface has to say, ranked;
put it somewhere legible on whatever box you were given."* Every screen that has needed that answer
has written it by hand, and the shape it takes is always the same — a ladder of viewport-height
guesses in screen code. The commissioning surface is the worked example: it re-derived a `vpH < 520`
threshold in game code and got it wrong twice, then shipped a landscape phone where 64 % of the
height was chrome and the one content band got 81 px — 2.7 rows inside a scroll — while a reserved
celebration box sat empty in the middle of the screen.

Two facts made that inevitable and both are framework-owned:

1. **The classifier is width-only.** A landscape phone and a portrait phone can be the same *width*
   class and need completely different compositions, because the scarce axis is height.
2. **There was no way to declare priority.** A screen can say "this is a VStack of eight things"; it
   could not say "these are eight things, ranked, each with a richest and a minimum-viable form,
   one of which may scroll and one of which holds a reserved box" — so the collapse policy had
   nowhere to live except in per-screen `if` ladders.

## Decision 1 — `UI.Composition` + `UI.Region`: a screen declares content, the framework decides placement

A new blueprint pair, and a new solver kind for each.

- **`UI.Region{ id, group, rank, floor?, sizing?, weight?, mayScroll?, mayDrop?, reserved?, children }`**
  — one ranked thing to say. **Its children are its forms**, richest first; the last is its
  minimum-viable form. Exactly one is shown; the rest keep their mount and are hidden.
- **`UI.Composition{ arrangements, groups, laneGap?, groupGap?, maxMeasure?, children = { Region… } }`**
  — the container. `groups` gives each set of regions a **lane affinity**, a sizing (`hug` / `fill`),
  an in-lane placement and an optional `minWidth`; `arrangements` is the ordered list of candidates.

**AMENDMENT (2026-07-31, director visual round 5 / DV5-1) — a group may SPAN.** The paragraph below
names the gap this closes: the commissioning spec's §S16.7 is "already a fourth shape (a masthead
that spans)", and the shipped vocabulary — a row of lanes, each stacking its groups — could not
express it, so the results surface kept its masthead outside the composition entirely (§S16.16-pre
records that as the one §S16.4 contract the mechanism did not have). DV5-1 then directed a
layout whose recap line spans the full width above three columns, which is the same shape a second
time. A group therefore declares **either** `lane` (an affinity an arrangement absorbs) **or**
`span = "above" | "below"`: its own full-width row, in that position relative to the band of lanes,
**in every arrangement**.

*Why a group flag and not a row vocabulary in `arrangements`.* The alternative — generalizing
`arrangements` from a list of lanes to a list of rows of lanes — is more powerful and answers a
question nobody asked: it makes every arrangement re-declare where the band goes, which is precisely
the thing a spanning band must not be free to disagree about (it is the element whose whole job is to
be in the same place in every resolution — Apple principle 4, *Familiarity*, and §S16.10's rule for
Skip). It would also oblige the three shipped preset NAMES to grow variants for any surface that
spans, which is a screen's code living in the library. The group flag says the one true thing —
*this band is not in the lane vocabulary* — and inherits every other group rule unchanged.

The row is the composition's full width, hugs its content, and its height comes out of **the same
budget the lanes share**: so a spanning region is a step-down/drop candidate whenever a lane
overflows (shortening it relieves every lane at once), never on a width failure (it cannot narrow
anything), and an empty span row is absent and costs nothing — "empty ⇒ absent", mechanically, one
level up. `sizing = "fill"`, `place`, `weight` and `minWidth` are **refused** on a spanning group:
each would be accepted and ignored, and slack stays with the lane band (rule 6). Additive by
contract and pinned as such — a declaration with no spanning group resolves to byte-identical
arrangements, forms, rects and rejections, and dumps `spans = {}` with the schema unchanged.

**The arrangement vocabulary is one thing, not three.** An arrangement is an ordered list of
**lanes**; a lane is an ordered list of the affinities it absorbs, sits beside its neighbours, and
stacks its groups down. The spec's three named resolutions are then just data —
`column = { {lead, main, trail} }`, `twoLane = { {main}, {lead, trail} }`,
`threeLane = { {lead}, {main}, {trail} }` — shipped as `composition.ARRANGEMENTS` and nameable as
strings, with a custom table accepted anywhere a name is. We chose the generalized vocabulary over
three hard-coded arrangements because the commissioning spec's own §S16.7 branch table is already a
fourth shape (a masthead that spans), and a framework that ships exactly the three cases one screen
named would be a screen's code living in the library.

**Nothing on either class is reactive.** `AdaptiveStack` binds an axis because the *author* decides
the axis; a Composition decides for the author, from the box it received. A reactive prop would be a
second source of truth about a fact the solver already measures — which is the exact defect this ADR
exists to remove. A `Readable` is therefore refused at construction.

## Decision 2 — the resolution is a PURE function, and the solver is only its measuring instrument

`src/layout/composition.luau` takes a declaration, an offer `{ w, h }` and a
`measure(regionId, formIndex, availW, availH)` callback, and answers the whole decision *including
geometry*: arrangement, per-region form, mounted/dropped, lane and group rects, the scroller, and a
`rejected` list carrying the rule every richer candidate broke. `solver.luau` supplies the measure
closure and consumes the rects.

This split is the point. The decision has no engine, no theme, no reactive core and no tree, so a
whole device matrix is a headless sweep — `resolve(decl, {w=733,h=313}, ctx)` and assert — instead of
a screenshot review. It also means measure and arrange cannot disagree: the resolution is computed
once per node per box and cached on the solve context, the same discipline `ctx.compact` already
carries for the compact-label verdict.

**The nine rules are ONE procedure, not a legality pre-test plus a solve.** (Eight at commissioning;
rule 9, empty-lane release, was added by the DV6-2 amendment under Decision 3.) The spec states legality
("the richest arrangement whose every region clears its floor at its minimum-viable form") and the
adaptation (step down, then drop, descending rank) separately. Implementing them separately would be
two procedures that can disagree, and the second one is the one that ships. So an arrangement is
legal *iff* running the full step-down/drop procedure inside it terminates with every lane fitting —
and that run IS the resolution.

**Two refinements we made deliberately, and why:**

- **A candidate must be able to relieve the failure it is asked to fix.** "Descending rank until
  everything fits", taken literally, degrades six regions to save one: on a width failure the only
  thing that narrows a hug lane is the region that *sets* its intrinsic width. So step-down and drop
  candidates are filtered to the failing lane and to regions that can actually help. This is what
  makes the general rule produce the spec's own worked case (§S16.12: "the CTAs drop to their column
  candidate before anything else moves") instead of needing it as a special case.
- **Rank ties break by declaration order** (later-declared gives way first), declared and pinned by a
  test. "Predict every device from the table alone" is only true if ties are not resolved by table
  iteration order.
- **A PINNED lane gives up nothing** (added 2026-07-31, found consuming the mechanism on the
  commissioning surface). "Is this region at the lane's intrinsic width" is necessary and not
  sufficient: when a region that *cannot* narrow (its last form, and not droppable) — or a group's
  `minWidth` — sits at that same width, nothing else in the lane can lower it, so degrading a tied
  neighbour cheapens the screen for zero pixels. The results surface's ceremony lane hit exactly
  that: a hero plate at the lane's own measure and a rivalry callout (rank 7, `mayDrop`) tied with
  it, so every landscape phone dropped the callout and the lane stayed the same width. A pinned lane
  offers no width candidates at all; the arrangement is then illegal and the next is tried with every
  region intact. Tied regions that can *all* give way still do, one at a time, in rank order.

## Decision 3 — floors are content, and `reserved` regions are held open BY their floor

A floor is `{ lines = n, role? }` and/or `{ targets = n }`, resolved against the live theme snapshot
on every solve — so a bigger type scale, a heavier package or a locale raises every floor by itself.
An authored pixel count is refused. Absent, a region's floor is its **minimum-viable form's own
measure**, which is the honest default: the smallest thing the author was willing to show.

`reserved` (the "nothing jumps under a thumb" flag) is implemented as *contribution never falls below
the floor*, and `reserved` **without** a floor is refused at construction. This is the one place we
chose a stricter contract than the spec stated. §S16.4 guarantee 8 says a reserved region "holds its
box at rest"; at rest a region's content measures nothing, so the only thing that can hold the box
open is a declared floor. A `reserved` flag with no floor would be a promise the mechanism cannot
keep — the accepted-and-ignored class the strict blueprint boundary exists to remove — so it is an
error rather than a silent no-op.

**AMENDMENT (2026-07-31, director visual round 6 / DV6-2) — the reservation is scoped to
MID-SEQUENCE, and an all-empty lane is RELEASED.** The rule above says *what* holds the box; it never
said *for how long*, and the consuming surface read it as "forever". On a quiet sponsor round —
hero suppressed, rivalry callout absent, celebration schedule finished — RascalRally's ceremony lane
held one reserved slot, could therefore never be empty, and spent 240 px of an 852-wide landscape
phone on a column with nothing in it while the results list scrolled four rows in what was left. The
director's reading: *"the left column is empty"*.

Two changes, and they are halves of one fact:

1. **`reserved` becomes a boolean the caller re-answers per solve** — the ONE reactive prop on a
   `Region`, and reactive for a reason the rest of the declaration is not. Every other field answers
   *what this region is*, a fact about the screen that the solver would otherwise have two sources
   for; `reserved` answers *is this region's schedule still running*, a fact about TIME that only the
   caller holds. Pinned `true` it is exactly what it always was (pinned byte-for-byte). Bound to a
   live read it holds the box **between two pieces of one sequence** — which is the reflow the
   guarantee was written for — and releases it once the schedule is provably done or never started.
   A live `reserved` is still a *reservation* at construction: the floor requirement and the
   `mayDrop` exclusivity both fire at the call site, because the read says when, never whether.
2. **Rule 9, empty-lane release** (Decision 1's ordered rules gain a ninth): a lane whose every
   region resolves to nothing paintable — empty, at-rest-invisible, or dropped — collapses. It takes
   no width and no lane gap, and what it would have held goes to the `fill` lanes by rule 6's own
   weights; with no `fill` lane the composition simply measures narrower. The lane is still
   **reported**, with `collapsed = true` and a zero-width rect at the x it would have started at,
   because "the left column is empty" and "the left column is not there" are the same screenshot and
   have to be different dumps.

The half a caller still owns: **the release is a property of what the region MEASURES.** A form that
paints a fixed box unconditionally is never empty however the flag reads — which is precisely what
the consuming surface did — so a slot that must be able to disappear puts its box behind the same
condition its flag reads. Both halves are pinned (`tests/composition.spec.luau` § rule 9).

## Decision 4 — re-solve, never rebuild; hidden is what removes a region from focus

An arrangement change is an **arrange pass**. Every form of every region stays mounted (ViewThatFits'
bargain at composition scale), a losing form and a dropped region get a zero rect plus
`hidden = true`, and the existing hidden-root machinery propagates that through the visibility walk,
the hit-rect walk and both focus paths. So a rotation, a window resize, a preferred-text change and a
theme swap keep scroll offsets, focus and in-flight transitions, and the specs assert zero factory
reruns, zero creates and zero removes across an arrangement change.

**Interpretation flagged.** §S16.4 guarantee 7 says "focus order follows declared rank". We implement
**focus order = declared region order**, which is arrangement-invariant (the real guarantee a pad user
needs) but is *not* rank order. Rank is adaptation priority; the spec's own §S16.11 focus order
(CTAs → field → Skip) is neither rank order (Skip and the CTAs tie at rank 1) nor visual order, so
rank cannot be the focus primitive without contradicting the spec that proposed it. Regions are
declared in **reading** order and walked in that order; a surface that wants a different focus path
uses the existing `navigationGroups` opt, which is where an explicit path already belongs.

## Decision 5 — the height half of `adaptive.conditions`, additive, on the same breakpoints

`adaptive.heightClass(h, opts?)` → `"short" | "medium" | "tall"`, `adaptive.orientationFor(w, h)`, and
six new conditions (`heightClass`, `isShort`, `isTall`, `viewportHeight`, `orientation`,
`isLandscape`). The ten-foot cap applies on the vertical axis too, for the same reason it applies
horizontally: `tall` is the densest vertical arrangement.

**The thresholds are `adaptive.BREAKPOINTS` itself, not a second table.** The question is identical on
both axes — how much content fits along this one — and a second set of literals would be a second
thing to justify, keep in sync and drift (this repo's own V15 finding was exactly a duplicated
breakpoint). A rotation therefore maps a class pair onto its mirror: 733×313 is `regular`×`short`,
313×733 is `compact`×`medium`.

These are a **coarse** fact for a screen that wants one; they are explicitly *not* how `UI.Composition`
adapts, which measures the box it received. `viewportHeight` is as raw as `viewportWidth` — no safe
insets, no overscan. The addition is additive by contract and pinned as such: a regression test fixes
the exact answer of every pre-existing fact across a width × distance-profile matrix, and the memo
count in `conditions` moved 6 → 12 (documented, and `opts.scope` owns all twelve).

## Consequences

- **Public surface added (amendment, 2026-07-31):** a group's `span = "above" | "below"`, the
  resolution's `spans` array and a region's `span` side, plus `spans` on the dump. MINOR bump;
  additive, and the additivity is pinned by a byte-for-byte resolution pin in `composition.spec`.
  Evidence: `tests/composition.spec.luau` § "a group may SPAN the composition as its own row"
  (11 cases: full width above/below in every arrangement, the lane budget, empty ⇒ absent, step-down
  and drop by rank, the width-failure exclusion, the hug measure, the dump, six refusals, and no home
  needed in any arrangement) + the mounted band and the gallery's `emptyRecap` / `fillRecap` steps.
  Two mutations run against the load-bearing checks (the lane budget, the row's width) — both fail
  the suite.
- **DV6-2 (2026-07-31) added:** a reactive `UI.Region.reserved` (`boolean | Readable<boolean>`) and
  rule 9's empty-lane release, with `lanes[i].collapsed` on the resolution and the dump. MINOR bump;
  additive in both directions — a pinned `reserved = true` resolves byte-for-byte as before, and a
  lane a reader already saw is dumped unchanged with `collapsed = false`.
  Evidence: `tests/composition.spec.luau` § "an all-empty lane COLLAPSES and gives up its width"
  (a six-row collapse matrix — measured-empty / dropped / released-reserve / active-reserve /
  one-still-paintable / all three together — plus the redistribute arithmetic to the pixel, the
  no-fill-lane case, mid-sequence stability across a release, the dump pin with its additivity pin,
  the non-boolean refusal, and the paints-unconditionally trap) + the mounted three-step case
  (piece ends → box held, nothing moves; schedule ends → lane collapses with zero factory reruns,
  creates and removes; next round claims it back) + the construction refusals with a live flag.
  Five mutations run against the load-bearing checks — the collapsed-lane report, the mount rule,
  the blueprint's live-reserve normalization, the prop's reactivity/dirty class, and the
  boolean refusal — and every one of them fails the suite.
- **Public surface added:** `UI.Composition`, `UI.Region`, `Facet.composition`
  (`resolve` / `normalize` / `dump` / `floorPx` / `arrangementOf` / `ARRANGEMENTS`),
  `controller.compositionAt(path?)`, `adaptive.heightClass` / `orientationFor` /
  `HEIGHT_BREAKPOINTS`, six new `conditions` Readables, and `composition` on the layout dump. MINOR
  bump; nothing removed, nothing changed meaning.
- **Cost:** every form of every region stays mounted. That is the same bargain `ViewThatFits` makes
  and the reason a re-solve is free; a surface with many heavy forms pays for all of them, and the
  fix is fewer forms, not a rebuild.
- **Diagnosability is now a first-class output.** An adaptive screen whose only evidence is a
  screenshot cannot be debugged: a screenshot cannot say that the three-lane candidate lost on the
  field lane's minimum width by six pixels. `facet-composition-dump/1` says exactly that, the
  solver publishes it on the node, the layout dump carries it, the controller exposes it, and the
  gallery scenario's report returns it.
- **Refused at construction, not resolved around:** unknown fields, a second `mayScroll`, `reserved`
  with `mayDrop`, `reserved` without a floor, a non-integer rank, a region with no forms, duplicate
  ids, a group with no home in some arrangement, an unknown arrangement name, a floor that states
  neither `lines` nor `targets`, and a non-`Region` child.
- **Evidence:** `tests/composition.spec.luau` (the pure decision matrix + the mounted re-solve
  identity + the gallery fixture headless), `tests/adaptive.spec.luau` (the height half and the
  additive regression pin), `examples/gallery/scenarios/composition.luau` (twelve regions through
  five device offers and a live axis flip). Eight mutations were run against the load-bearing checks
  — rank direction, step-before-drop, the reserved floor, the one-scroll refusal, the
  buys-a-pixel filter, arrangement preference order, the hidden mark and the width breakpoint — and
  every one of them fails the suite.

## Alternatives considered

- **A recipe instead of a class** (AdaptiveStack + ViewThatFits + hand-written spacers, per §S16.4's
  *Interim*). Expressible for two of the three arrangements, and it is exactly what produces a
  per-screen height ladder: the priority table has nowhere to live, so the collapse policy becomes
  code. Rejected as the thing DV4-3 named.
- **Reactive props driven by `adaptive.conditions`.** Simplest to build, and wrong: it re-derives the
  screen's box from the viewport, which is the bug (a windowed pane, a safe-inset device and an
  overscanned TV all lie). The mechanism must measure.
- **A stateful `reserved` box remembered across solves.** Would deliver "never reflows" without an
  authored floor, at the cost of making the resolution impure and history-dependent — untestable as
  a sweep, and non-deterministic across a remount. Rejected in favour of the declared floor.
