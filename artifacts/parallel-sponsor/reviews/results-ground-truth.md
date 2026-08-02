# Results screen — extraction ground truth for the S16 v2 redesign (2026-07-31)

Produced by the redirected ladder-extraction round (reads only; suites
verified 2768/2632, zero file changes). The designer's factual substrate.

## 1. Information carried, per role (cites = client/SponsorResults.luau)

- **Header, both roles:** banked-coin chip (wallet :294 + `+gain` :296; ladder
  full→total-only→hidden per ResultsLayoutModel.headerLayout); centred "Next
  race in: N" (:234); Skip chip 44×44 top-right (:1577/:1580, M12 §4.4).
- **Hero, role-split:** racer = placement slam, 160 px plate, cap 44
  (:1267-1287); sponsor = Round-Story line, cap 24 (:962-980). Legacy shows
  the slam to BOTH; the role split is the port's spec ruling.
- **Standings @ RESULTS** (ResultsSpotlightModel.standingsContentFor:313):
  racer → placement rows (rank 18 / 28 px badge / name 20, rowH 36|30);
  sponsor → drama recap line, cap 20 (:982-998); + FTUE reward row when
  granted (cap 18). Port adds placement rows for the sponsor (logged diff).
- **Standings @ INTERMISSION → roll-call:** "ON THE GRID" 12; ≤8 seats (40 px
  plate, 24 swatch, name 18, ★you/⚑rival); rivalry callout 16; "RACE
  SPONSORS" 12 + chips (★ human); human-count line.
- **CelebrationSlot, one piece at a time:** economy (RP bar + tier 12 +
  streak 14) → award (title 18 + reason 14) → payoff (line 20 on plate). RM:
  all simultaneous/static as appended rows.
- **CtaBand:** optional bait chips 13; optional tease 16; CTAs 170×52 cap 22,
  emphasis follows the SELECTED role (:855-857).

## 2. Legacy's landscape ladder + measured shortcomings at 733×313

Ladder (M12 §4.5): hero→28 chip · standings caps top-4+you, remainder scrolls
· celebration→44 · celebration→0 · hero→0 · header→0 · bait→0; CTA + Skip
never condense. At 733×313 it lands rung 2:
- **64 % of height is chrome**; the ONE content band gets 81 px = 2.7 compact
  rows → the capped 5-row list scrolls at ~54 % visible — **legacy's own
  landscape answer IS a tiny scrolling view**;
- the CelebrationSlot's 76 px (24 % of height) is reserved for a transient and
  deliberately RESTS EMPTY after celebrationEndS — most of the "empty space";
- 733 px of width carries one 0.8-width centred column — portrait logic
  rotated, never a landscape composition;
- the slam (the emotional payload) is a 28 px chip while the celebration keeps
  76 px.

## 3. Hard constraints for ANY design (contracts, unchanged)

- **Timing:** RESULTS 7 s → INTERMISSION 6 s → GRID 4 s (TailChoreography);
  standings→roll-call swaps ONCE at the RESULTS→INTERMISSION edge; every
  schedule read = pure function of (tick − phaseTick)/tickHz (mid-tail joiner
  gets the right beat).
- **Skip:** RESULTS + INTERMISSION skippable, GRID not; skip = skip-ALL to the
  settled state (slot never goes dark); three affordances behind ONE gate,
  tail-scoped latch; Skip 44×44 top-right, never condensed.
- **Celebration:** economy → award → payoff, contiguous, never concurrent
  with the slam; read floors 1.2/2.5/2.5/1.6 s; late award splices; RM
  simultaneous/static; the slot must not reclaim space at rest (no CTA jump
  under a thumb); no fact reachable only during a transient.
- **Safe areas/touch:** rootPolicy deviceSafeContent (insets once); CTA + Skip
  44 px minimum + BOTTOM_BREATH 12; zero overlap provable via
  HudZoneModel.findOverlap at pinned viewports.
- **Type:** A15 — legacy caps, nothing resolves a type role on this surface;
  floor 12; slam ≤44; strings from TailCopy/SponsorHudModel/SponsorSignature;
  proper nouns AutoLocalize=false.

Key files: SponsorResults.luau, ResultsLayoutModel.luau,
ResultsSpotlightModel.luau, LuauUISponsor/ResultsScreen.luau + ResultsParts,
M12_UI_FIX_SPEC §4.4-4.7, UI_SPEC_sponsor_luauui §3.2b/§S16.
