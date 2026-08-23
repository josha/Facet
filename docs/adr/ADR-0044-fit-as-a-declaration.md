# ADR-0044 — "Does it fit?" is a declaration and a value, not a formula each consumer writes

**Date:** 2026-08-22
**Status:** Accepted
**Number:** 0044. 0043 is collections measure-and-name; 0045 (tab-view accessory
slots) landed in a concurrent lane of the same campaign.
**Companions:** [ADR-0040](ADR-0040-unreleased-breaking-changes.md) rows **B-22**
and **B-23** (the two behaviour changes this ruling required),
[ADR-0019](ADR-0019-theme-packages.md) §6 (typography roles carry the face and the
line height), [ADR-0039](ADR-0039-ten-foot-metric-ladder.md) (the ladder the four
wrong copies could not ride), `docs/reference/api.md` §`textSize` and
§`ViewThatFits`, `docs/handoff/SOURCE_CAP_LEDGER.md` (the solver row whose
extraction had to precede this).
**Audit:** `framework-gaps-phase2` §10 (`Facet.text` is a function where consumers
need a prop) and §2 (`ViewThatFits` has no value-form, and its natural spelling
silently breaks it). §10 is the only gap in that audit that was **shipping wrong
pixels**.

## Context — one question, three shapes, and only two of them existed

The framework could answer "does this text fit this box?" and "does this content
fit this container?" It could only answer them in **one shape each**, and neither
shape was the one consumers reached for.

* **Text.** `Facet.text.fit` is a function. A consumer wanting a size that fits a
  box had to build a memo, read the environment, name a font and thread the
  result back into a prop — *per site*. A character count times a guessed constant
  is one line. api.md's own `text` section records the outcome: a survey run in
  2026-08 found **seven near-duplicates of that formula in this repository and
  exactly one of them correct** — a dated finding, re-run 2026-08-22 and now **zero**
  (see Consequences). Rascal Rally's Sponsor package alone held four,
  each mirroring the framework's private `AVG_GLYPH_FRACTION = 0.62` and
  `LINE_HEIGHT_FACTOR = 1.2` under a comment naming the source.
* **Layout.** `UI.ViewThatFits` returns a **subtree**. A consumer needing the fit
  *decision* — to reserve space in a sibling, to place or skip a minimap, to
  choose between two whole surfaces before either is built — had nothing to call:
  `adaptive.conditions` is viewport-relative by construction, and api.md says so.

The two gaps have the same shape, which is why they were one round: **the
framework owned the answer and did not offer it in the form the caller needed**,
so the caller wrote their own, and the copies were wrong in ways nobody could see.

## Decision

### 1. `textSize = "fit"` — the size, as a declaration, resolved in the solver

`textSize` accepts `"fit"` and the option form
`{ fit = { cap = <role or px>, floor = <role or px> } }` on every text-bearing
class. It is resolved **inside the solver**, where the box, the face, the
typography scale and the paint offset all already are — the audit's stated home,
and the only place the four constants cannot be copied wrong.

* **`cap` defaults to the class's own intrinsic role**, so `"fit"` can only ever
  make text smaller, never bigger.
* **`floor` defaults to the theme's `caption`**, which every package is required
  to carry (`themes/package.REQUIRED_TYPE_ROLES`). A theme-owned floor survives a
  package swap and the ten-foot ladder; `text.fit`'s own raw default of `1` would
  let a label paint unreadably rather than let the layout decide.
* **The band is in PAINT units.** Every other size on the measure seam is scaled
  by `max(typographyScale, typographyPaintScale)` — the deliberate over-reserve
  that exists because the engine adds the player's preference *additively* at draw
  time. A fit node has no authored size to over-reserve for: the solver picks the
  size that will actually be painted, so the band it picks from is the band paint
  lives in and the reserve is exact rather than generous. Using the measure scale
  would let a fit label grow by the preference **and** take the engine's additive
  offset on top — `text_metrics.reservedSize`'s own double-application warning,
  spelled the other way round.
* **It is `text_fit.fit`, not a second search.** The public helper already owns
  the binary search, the conservative-by-inheritance direction and the "fit the
  painted form, return the authored size" split. A private copy in the solver is
  precisely how the eighth near-duplicate gets written.
* **The paint seam reads the solve's answer**, recovered by an identity rather
  than a new channel: `textFacts.size` is what the measure used, which for every
  text node is what the engine will draw, so the size to write is that minus the
  same offset.

**One reading of the grammar, three seams.** `text_fit.fitSpecOf` is called by the
schema's acceptance check, by `render/layout_node.textOf` and by
`render/commit_walks.textScale`. A second reading is how `"fit"` ends up meaning
two things.

### 2. `hug` inside a `ViewThatFits` candidate is fixed, not refused

The audit and the house doctrine both leaned *refuse loudly at construction*. The
investigation found a sound value-form instead, and it is the ladder's **own**
doctrine rather than a new rule: ruling 2 (2026-08-14) already says a candidate is
judged at its ideal size, and `ctx.fitProbe` already makes every mechanism that
squeezes a view invisible for the duration of the probe. `hug`'s cap-at-the-offer
*is* one of those mechanisms — the same family as truncation, `lineLimit` and
`shrinkWeight` — so the probe suppresses it too, and the ladder's existing
`w <= availW` test then answers correctly.

**Why not refuse.** A refusal would have been aimed at the wrong author: `Callout`,
`Menu`, `LevelPicker` and a `TabView` band each choose `hug` for themselves, so
`UI.ViewThatFits{ children = { UI.Menu(...), … } }` would have been refused for a
spelling its author never wrote, with no fix available but a wrapper that changes
the semantics. Refuse-don't-guess governs the cases where the framework would have
to *guess*; here it can compute the honest answer.

See ADR-0040 **B-23** for the blast radius and the instrument.

### 3. `adaptive.fitsIn` / `adaptive.fits` — the container-relative decision as a value

`fitsIn(needs, container, clearance?)` is pure and is **the ladder's own
predicate**: `chosenCandidate` tests `availW == math.huge or w <= availW` and so
does this, driven side by side across a width sweep in
`tests/fits_ideal_size.spec.luau`. A screen that reserves room for an arrangement
the solver then refuses to use is worse than one that never reserved, so there is
one comparison rather than two.

`fits(core, spec)` is the reactive half, and its `needs` takes a **list of parts**
rather than a pre-computed sum. That is the whole design:

* a part that goes stale is invisible inside a sum — the sum still looks like a
  number;
* a part that goes missing makes a sum **smaller** and the verdict **more
  permissive**, i.e. it fails in the unsafe direction;
* a sum computed once cannot ride the ten-foot metric ladder that moves the very
  parts it summed.

So a static part that is not a number, and a list with a hole in it, are refused
at construction; a live part that resolves to `nil` reaches `core:lastError()` and
the decision holds its **last good** answer rather than inventing a new, wrong,
confident one. (A memo's compute is pcall-quarantined by the reactive core, so a
loud refusal has to happen at construction and can, for everything knowable
there — that split is forced by the core, not chosen.)

## Consequences

**The census, re-run.** The "seven near-duplicates" above is a 2026-08 finding and
this round is the second half of closing it. Re-run 2026-08-22 over `src/` and
`examples/`: **zero** box-or-fit derivations remain outside `text_metrics` itself —
the 2026-08-15 line-box round moved the PREDICTING sites onto `text.facts`/
`text.lineBox` and this one moved the FITTING sites onto the prop. One use of the
glyph fraction survives and is deliberately excluded: `src/present/text_reveal.luau`'s
`REVEAL_GLYPH_EM` is a travel RATE (glyphs per second times an em times the painted
size), not a box, and neither face of `text_fit` expresses it.

**What it closes, measured.** Rascal Rally's `StartCountdown` deleted both mirrored
constants and declares `textSize = "fit"` with the plate as its ceiling; its
numeral was **one full step smaller than the plate could hold** under the estimate,
at every preference. `RolePickScreen` deleted `GLYPH_EM` and now spends
`Facet.text.fit`/`.measure`; the shipped English copy lands on the same numbers,
and where it does not — the two-line CTA budget at a raised preference — the
estimate was the wrong one: it assumed a two-line box packs perfectly, and no
greedy wrapper does. `HudZoneModel.sponsorTopStrip` decides the topbar rung from
named parts through `adaptive.fitsIn` instead of `GROUP_NATURAL_W = 100 + 10 + 200`
and a `TOPBAR_SLACK = 24` whose own comment admitted it was guarding a guess.

**What it deliberately does not close.** `textSize = "fit"` gives the size to the
solver and hands nothing back to the consumer, so a screen that must *derive its
box from the chosen size* — Rascal Rally's role-pick CTA pair, where a director
ruling says the two buttons read at ONE size and the popup grows rather than the
type shrinking — cannot use it, and correctly keeps the size as a value. The prop
shrinks text to fit a box; that screen grows a box to fit text. Booked: the
solver's chosen size as a readable, which would close the last of it.

**`ResultsParts.lineBox`'s `1.25` stays.** The audit names it as one of the three
wrong copies and it is one, but `tests/facet_line_box_contract.spec.luau` had
already RECORDED it as a deliberate over-reserve with a measured margin and named
the director as the person who may lower it. That case is older than this round
and it is a decision about shipped geometry, not a fact about a number. It was
lowered during this round and put back; the measurement (`ledgerBodyHeight(0)`
40 → 39, and 1 px off each of the four RP row boxes) is recorded in the case. The
prop does not force the question either way: `lineBox` predicts a **box** from a
size, while `textSize = "fit"` picks a **size** from a box.

**Cost.** A fit node pays one `text_fit.fit` per measure — a spec-table allocation
and ~log2(cap) memoized measures — and forces the lazy `content()` that a node with
two fixed dimensions otherwise skips. Both are bounded to nodes that declared the
prop, and the second is the compact ladder's own precedent, recorded directly above
it in `measureUncached` for the identical reason.
