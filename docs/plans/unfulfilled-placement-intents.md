# Unfulfilled placement intents — the director's queue

**Opened 2026-08-13, by the §2.1 silently-inert-placement-prop audit**
([`swiftui-parity-round2.md` §2.1](swiftui-parity-round2.md#21-stacks-parity-audit--done-and-it-found-a-defect-class)).

`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `gridSpan` and —
since the Milestone-1 architecture review (C2) — `layoutPriority` and
`shrinkWeight` are shared BOX props — legal on every node — but each is an instruction addressed to a
particular kind of **parent**, and every arrange branch reads only the ones it
knows. Everywhere else the framework accepted the prop and then ignored it. The
audit (`solver.auditPlacement`, reported through `controller.diagnostics()`) now
says so out loud; this file is what happened to the twelve live call sites it
found. (The shrink pair joined the watched set after this queue was
written; the audit found no new live call site for either, so no row below moves.)

**The ruling that produced this file.** Deleting an inert prop moves **zero
pixels by definition** — that is what inert means — so every deletion below was
taken without further authorization. **Migrating** a prop to a spelling that would
actually work is a different act: it moves pixels, and it is a product call. None
of those were taken. This file is that decision queue.

**How to read a row.** Every "would move" figure below is a *measured* rect from a
live headless mount, not an estimate — the method is at the bottom. A row's
migration is written out so the decision is "yes/no", not "go and work it out".

---

## Queue — an intent an author expressed and never got

### 1. Rascal Rally — the omen column never centres its cap or its tail

| | |
|---|---|
| File | `games/RascalRally/code/src/client/FacetSponsor/OmenBillboard.luau` |
| Nodes | `/Omen/OmenStack/HelpCap`, `/Omen/OmenStack/HinderCap`, `/Omen/OmenStack/Tail` |
| Parent | `OmenStack`, a **vstack** |
| Prop deleted | `alignH = "center"` on each |
| Intent | centre the family form-cap and the tail in the billboard column (§8's non-hue channel) |

A stack reads no `alignH` off a child, so all three have always painted at the
column's **leading edge**. Measured on the live billboard: `OmenStack` is 120 wide,
the cap is 22 wide at x = 0, the tail is 10 wide at x = 0.

**Migration:** add `lineAlign = "center"` to each of the three.
**Moves pixels:** yes — the cap shifts **+49 px**, the tail **+55 px**, on every
omen billboard in the game. This is the single largest visual change in the queue.

### 2. Rascal Rally — the autoscroll chevrons never get their 2 px inset

| | |
|---|---|
| File | `games/RascalRally/code/src/client/FacetSponsor/RacerList.luau` |
| Nodes | `AutoscrollChevron_top`, `AutoscrollChevron_bottom` |
| Parent | `RacerListRegion`, a **zstack** |
| Prop deleted | `offsetY = ±m.autoscrollChevronInset` (2 px) |
| Intent | legacy `SponsorGui:962` — "2 px off the armed edge" |

A zstack reads `alignH`/`alignV` off a child but not `offsetX`/`offsetY`, so the
chevrons have always sat flush against the band edge their `alignV` pins them to.

**Migration:** `margin = { top = m.autoscrollChevronInset }` on the top chevron and
`margin = { bottom = … }` on the bottom one (a zstack's arrange does honour
`margin`), or wrap each in a `UI.Anchor`. The metric is deliberately left defined
in `TableMetrics.luau` — it is a theme token, and it is what the migration spends.
**Moves pixels:** yes — 2 px each, only while an edge is armed.

### 3. Rascal Rally — §6's chip-row reflow was never implemented

| | |
|---|---|
| Files | `games/RascalRally/code/src/client/FacetSponsor/ChipRow.luau`, `…/init.luau` |
| Node | `/SponsorChips/…/ChipBand/ChipRow` |
| Parent | `ChipBand`, an **hstack** |
| Props deleted | `anchor = "top"`, `offsetY = opts.bandOffsetY` — plus the now-dead `bandOffsetY` option and its call site |
| Intent | UI spec §6: "when the band cannot hold the group, the whole row reflows to a second row below the bar" |

Two independent reasons nothing ever moved: an hstack reads neither prop off a
child, **and** spec amendment A8 had already ratified `bandOffsetY` to a constant
`0` (the band is reserved instead). Measured: the band solves to y 66 h 44 and the
row to y 66 h 44 — the row already fills the band, so even the `anchor = "top"`
half was a no-op. `ChipRow.luau`'s file header claimed the reflow as a shipped
behaviour; that claim is corrected in place.

**Migration, if §6 is still wanted:** wrap `ChipRow` in a `UI.Anchor` that fills
the band and put `anchor`/`offsetY` on the row inside it — an Anchor parent is the
one kind that reads them.
**Moves pixels:** only if the offset becomes non-zero again. **The real decision is
not the migration — it is whether §6's reflow is still a requirement at all**, given
A8 superseded the problem it solved. If it is not, this row closes as "withdrawn".

### 4. Facet reference proof — Glade's "Best value" chip never right-sets

| | |
|---|---|
| File | `examples/reference/p1_glade/ui/shop.luau` |
| Node | `/ProvisionShop/…/Pack_starlightBundle/BestValue` |
| Parent | `Pack_*`, a **vstack** |
| Prop deleted | `alignH = "end"` |
| Intent | the decorative chip caps its own growth and sits at the card's trailing edge |

Measured at the proof's default 1200 px viewport: the pack is 1152 wide, the chip
is 75 wide at the card's leading inset.

**Migration:** `lineAlign = "end"` on the chip.
**Moves pixels:** yes — about **+1045 px** at 1200 px wide (it is a full-width card),
proportionally less on a phone.

### 5. Facet gallery host — the theme picker's chip never right-sets under its panel

| | |
|---|---|
| File | `examples/gallery/client/theme_picker.luau` |
| Node | `/GalleryThemePicker/Dock/Shell` |
| Parent | `Dock`, a **`UI.Anchor`** |
| Prop deleted | `alignH = "end"` |
| Intent | right-align the collapsed chip and the open panel inside the top-right column |

An Anchor places by corner and reads no align at all. Measured with the panel open:
the Shell column is 560 wide, the `Toggle` chip is 103 wide at the column's leading
edge, the panel is 544 wide.

**Migration:** `align = "end"` on the Shell VStack — the *container's* cross-axis
word, since `alignH` is not one. (`lineAlign` is the per-child spelling and is the
wrong tool here: the request is about the Shell's own children.)
**Moves pixels:** yes — the collapsed chip jumps **+457 px** to the right whenever
the panel is open. This is example-host chrome, not product UI.

---

## Recorded, no queue entry needed — the prop was redundant

Each of these was inert *and* the thing it asked for was already true, so deleting
it lost no intent. Verified rather than assumed: every "already" below is a solved
rect or an explicit solver rule.

- **`games/…/TableScreen.luau` `Split/ListBand`** — `alignH`/`alignV`. The parent
  `Split` declares `align = "stretch"` and the band declares a `fill` on both axes,
  so it already takes the whole cross extent. Nothing to align.
- **`games/…/ResultsScreen.luau` `CtaFit/CtaRow`** — `alignH`. A `ViewThatFits`
  gives its chosen candidate the whole offer, and the row declares `width = FILL`,
  so it already spends all of it.
- **`games/…/HudScreen.luau` `ChipBand`** — `alignH`. Its parent is an Anchor
  (reads no align), and the band's two `fill` Spacers are what actually centre the
  group — legacy's own 0.5-anchor dock, expressed the stack's way.
- **`games/…/OmenBillboard.luau` `OmenCaption`** — `alignH`. Unlike the cap and the
  tail beside it, the caption declares `width = FILL`; a stack gives a `fill` cross
  dim the whole line, so `lineAlign` would have nothing left to move. Its centring
  is `textAlign` inside a box that *is* the column.
- **`examples/reference/p1_glade/ui/overview.luau` `Line/TwoLines`** —
  `alignH = "start"`. Inert twice: a `ViewThatFits` reads no placement prop, and a
  stack's own cross-axis word is `align`, whose default is already `start`.
- **`examples/gallery/client/init.client.luau` `ShowcaseChrome/Dock/Bar`** —
  `alignH = "start"`. Same pair of reasons, and the column is `width = FILL` anyway.

### Two the previous audit filed as unfulfilled that measurement moved back

Both are recorded here rather than in the queue **because the measurement said so**,
and both carry the same footnote: the prop was a *fragility guard* that never
guarded anything, so deleting it removes an intention the layout currently
satisfies by accident of its own sizing.

- **`games/…/FollowScreen.luau` `WatchedCard/WatchedText`** — `alignH = "center"`,
  a MAIN-axis request under an hstack that `lineAlign` structurally cannot carry.
  Measured on all three size classes: the card hugs 60 + 260 + 60 = 380 and the
  text column solves to x = 60 inside it — **exactly centred already**, by the fixed
  width plus the hugging row. The file's own comment says the prop was there so
  "the two cannot disagree the day a child stops filling"; that day would have
  found the guard dead. If the card ever stops hugging, the fix is
  `distribute = "center"` on `WatchedCard`.
- **`examples/reference/p5_wardrobe/init.luau` `BuyBarWhen/then/BuyBar`** —
  `alignV = "end"`, also a main-axis request under a vstack. Measured:
  `PreviewCol` solves to y 54..900 and the bar to y 854..900 — **already flush with
  the column's bottom edge**, because the preview above it fills and leaves no
  slack. If that ever changes, the fix is a `fill` Spacer above the bar or
  `distribute = "end"` on the column.

### One node the audit deliberately does not police

`games/…/OmenBillboard.luau` `PlateStack` is a `UI.ZStack` carrying
`alignH = "center"` under the same `OmenStack` vstack. It is **not** reported and
**not** deleted, because a ZStack *does* read its own `alignH` as the default for
its children — the `SELF_READ` case in `solver.auditPlacement`, and the one a naive
read table gets wrong. The author probably meant "centre me in the column" (which
does not happen) rather than "centre my children" (which does). Flagging it would
mean flagging every legitimate `UI.ZStack{ alignH = … }` in the codebase, so the
ambiguity is recorded here instead of made noisy there.

---

## Already closed, before this file opened

`src/controls/row_actions.luau`'s floating `Menu` was the one **framework** call
site in the audit, and the loudest defect in it: the menu asked to sit at its
trigger's screen coordinates and was placed at the origin, silently, with an empty
`diagnostics()`. It was found by this audit and fixed inside the hosted-row-actions
round — the Anchor now fills the edge-to-edge surface and the placement rides
`MenuRows`, its child, where an anchor-kind parent actually reads it. Re-verified
2026-08-13: the audit no longer reports it.

---

## Method, so a number here can be checked

Every figure above comes from a live headless mount over `FakeTarget`, read out of
`controller`/`adapter` solved rects, using the surface's own existing spec harness:

| Row | Harness driven |
|---|---|
| Omen column | `games/RascalRally/code/tests/facet_sponsor_omen.spec.luau` (`world` + `omenBeat`) |
| Chip band / row | `games/RascalRally/code/tests/facet_sponsor_story.spec.luau` |
| Watched card | `games/RascalRally/code/tests/facet_sponsor_table.spec.luau` (all three size classes) |
| Glade shop | `tests/reference/glade_spec.luau` (`world`, tap through to the shop) |
| Wardrobe buy bar | `tests/reference/wardrobe_spec.luau` |
| Theme picker | `tests/gallery_theme_picker.spec.luau` |

The full live-call-site list was produced by instrumenting `solver.auditPlacement`
to print every finding — hidden subtrees included — and running **both** complete
suites, then re-confirming each hit against solved rects. That instrumentation was
temporary and is not in the tree; the standing mechanism is the audit itself, which
now fails nothing and reports everything on `controller.diagnostics()`.
