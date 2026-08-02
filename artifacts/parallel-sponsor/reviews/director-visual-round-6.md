# Director visual round 6 (2026-07-31, verbatim)

"the finishing countdown is either at the very edge or overflowing the
countdown box. the text needs to be better aligned. and the composition view
doesn't look right — the left column is empty, and the rhoda rhino pill is at
the bottom?"

| # | Item | Reading |
|---|---|---|
| DV6-1 | The finishing/grace countdown chip clips its label ("Finishi…") and the numeral hugs/overflows the edge (director's crop: flag glyph + truncated text + "7" at the box edge) | The race-chip's GRACE/FINISHING form: text fit + alignment broken. Determine whether it is OUR ChipRow grace form or the legacy ShowrunnerPill (the crop has no dev tag visible; suspect ours). Fix to legacy's chip metrics: the box fits its longest label + numeral at the shipped sizes, centred, on every view row |
| DV6-2 | On a quiet sponsor round the LEFT column renders EMPTY (hero suppressed, no streak, celebration resting) yet still reserves its width; and the rivalry callout ("Rhoda Rhino is on the grid. Race them!") renders at the BOTTOM instead of in the left column per DV5-1 | Two defects: (a) the rivalry region is NOT in the ceremony lane as DV5-1 directed (pixels show a bottom span/row) — put it in the LEFT column; (b) an all-empty lane must COLLAPSE and give its width to the fill lane — a framework rule (empty-lane release), public + tested. The "reserved box never reclaims at rest" contract is scoped to MID-SEQUENCE stability (no reflow under a thumb while pieces run), not to rounds where the schedule provably has nothing to show |

## As shipped (2026-07-31)

Suites: game **2793 → 2801**, LuauUI **2729 → 2743**, both green; stylua clean; 11/11 frozen legacy
checksums unchanged. Ledger row **OWN-D48**; ADR-0023 amendment under Decision 3; spec **§S16.18**.

**DV6-1 — the culprit is OURS.** Reproduced headless before anything was changed: at 844×390, grace
phase, the chip solved to `x=268 y=68 w=101 h=40` and the numeral to `y=91 h=24` — bottom edge **115
against a chip that ends at 108**, i.e. 7 px outside its own plate, and start-aligned at the block's
left rail under a 75 px caption. The legacy `ShowrunnerPillGui` is *not* the culprit: it draws a glyph
inside `SponsorWidgetKit.buildCountdownRing` and has no label or numeral at all, so it cannot produce
the director's crop.

The cause was one substitution: legacy's grace form is four ABSOLUTE placements with their own size
caps (`SponsorGui:1412-1462`), and round 1 ported it as one padded stack in the `caption`/`heading`
type roles — 15 px caption + a 4 px `xs` gap + 24 px numeral = 43 px of content in the 32 px a 40 px
chip's 4 px padding leaves. Fixed to legacy's own metrics, now in `StoryTokens` with their citations
(flag 18 at x = 8, block at x = 34, caption ≤ 12 and numeral ≤ 18 stacked FLUSH and CENTRED over each
other), with legacy's 40 px as the chip's `hug` **floor** rather than a fixed cage — so a longer
localized label widens the chip instead of truncating into it. The lap read keeps its box because the
4 px inset moved onto the LABEL, where legacy has it.

**The collapse contract, as shipped** (LuauUI composition **rule 9** + a reactive `Region.reserved`):
a lane whose every region resolves to nothing paintable — empty, at-rest-invisible, or dropped —
collapses: no width, no lane gap, and the release goes to the `fill` lanes by rule 6's weights (with
no fill lane the composition simply measures narrower). It is still REPORTED, `collapsed = true` with
a zero-width rect at the x it would have started at. Rule 7 is SCOPED, not withdrawn: `reserved` takes
a `Readable<boolean>` — "can this schedule still produce a piece" — and holds the box through every
gap inside a sequence exactly as before. The half the caller owns is documented: the release is a
property of what a region MEASURES, so a form that paints a fixed box unconditionally is never empty
however the flag reads (which is precisely what this surface did).

**DV6-2(b) — the root cause is a MIS-READ, not a drop or a step-down.** The pill is
`TailCopy.promoBaitRival` ("{rival} is on the grid. Race them!") = region **`Bait`**, and the line
above it in the earlier capture is `promoTeaseStreak` ("⚡ Hot Streak: +N Coins next race!") = region
**`Tease`**. Those are the two strings DV5-1 named for the left column, verbatim. Round 5 read them as
the celebration's streak chip and the roll-call `BogeyCallout` (copy `rollcall.bogey.*`, absent
outside INTERMISSION), concluded the ceremony was already right, and moved `Bait`/`Tease` into the
**field** group with RACE SPONSORS — so they rendered under the standings at the bottom of the middle
column, exactly as the DV5 capture shows. Both are `ceremony` now, ranks unchanged.

## What the lead's captures must confirm

1. **The grace chip, live, mid-grace** (landscape phone and portrait): "Finishing!" complete — no
   ellipsis — with the numeral CENTRED under it and fully inside the plate, both clear of the rounded
   corners. Two digits (t ≥ 10 s remaining) is the case to catch.
2. **A quiet sponsor round in landscape, after the tail** (~14 s in, no promo): **no left column at
   all** — the results list flush against the panel's left edge and the two CTAs against its right,
   with no dead band between them.
3. **A quiet sponsor round WITH the promo pair**: "Rhoda Rhino is on the grid. Race them!" and the
   Hot Streak line in the **LEFT column**, left of the list — not under it.
4. **A celebratory round** (during the economy piece): three columns, with the rivalry pill and the
   streak line stacked UNDER the celebration slot in that same left column, and nothing moving when
   the piece lands or ends.
5. **Skip mid-tail**: the slot must stay up with the settled economy — the left column must not
   vanish under the thumb that skipped.
