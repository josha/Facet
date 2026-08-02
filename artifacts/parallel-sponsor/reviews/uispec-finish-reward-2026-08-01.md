# UI spec — the finish screen's reward, and two racing-HUD overflows

**Role:** UI Designer · **Date:** 2026-08-01 · **Status:** build contract, pending the `UI-SPEC` gate
**Binding input (content, not re-litigated):** `design-finish-reward-2026-08-01.md` (Game Designer)
**Amends:** `UI_SPEC_sponsor_luauui.md` §S16 (A28 · A39 · A41 · A42 · A43), `FTUE_ECON_REVEAL_SPEC.md` §10
**New amendments in this document:** **A46 – A53** (the series' last used number was A45)

---

## 0. What this document decides, in one paragraph

The game designer cut the finish screen down to three content elements — **your place**, **the field**,
**the Rally-Points line** — and forbade three things: rotating an earned fact out of view, moving a
region after t=0, and narrating Coins. This spec is the buildable form of that: **seven regions instead
of twelve**, **one new type role (`rpDelta` = 34) that makes the reward the second-largest thing on the
screen**, **a latched-condition rule that makes the composition's geometry a function of the offer
alone and never of the clock**, and **a five-beat motion score in which exactly one element moves at a
time**. Plus the race HUD finally clearing at the finish (a one-line regression in
`LuauUISponsor/init.luau`), and two racing-HUD text-overflow bugs fixed with numbers.

### The invariants this surface now defends (quotable, one line each)

1. **Geometry is a function of the offer, never of the clock.** Every region reserves its box at the
   first solve and holds it for the screen's life. Only *paint* changes with time.
2. **The numeral is the reward; the bar is the map.** The RP delta is the second-largest thing on the
   surface after the hero, and it never lives inside a track.
3. **Hue is currency identity, and nothing else.** Gold (`coin`) = Chaos Coins. Orange (`accent`) =
   Prestige / Rally Points. A second meaning never becomes a second shade.
4. **Ledger is stated once and stays stated; only the one commentary box ever changes content.**
5. **Rows and racers carry no rings, strokes, marker bars, or slash marks. Ever.**

---

# PART A — THE FINISH SCREEN

## A.1 Region inventory after the cut

### A.1.0 What is gone, and what that means mechanically

| Cut | Was | What its removal means |
|---|---|---|
| `FieldHead` (R7) | the reward-earned row ("New sticker for your kart!"), the recap, `ON THE GRID` | **The whole region retires.** Its reward row is the sticker line the designer cut (§3.1); its recap moved to the `caption` span row at DV5-1; its `ON THE GRID` label rides the roll-call band A41 already stopped mounting. Nothing is left to hold, so the region is deleted rather than left to measure zero. `TYPE.reward` (18) becomes unreachable. |
| `Sponsors` (R9) | RACE SPONSORS header + chip strip + human line | Already never mounts at RESULTS (A41). The region is deleted from the declaration so it cannot measure zero and cannot be resurrected by a future `standingsContent` edit. |
| `BogeyCallout` (R10) | the rivalry callout | Re-homed to the pre-race window by A43. Region deleted. |
| `Bait` (R11) / `Tease` (R12) | promo pill + hot-streak line, two ceremony regions | **Merged into the one commentary box** (§2.3: "Commentary gets one lane and it is the only lane that ever changes content"). They stop being regions and become two more entries in the commentary rotation. DV6-2's ruling that they belong to the ceremony lane is preserved — they are still there, in the box directly under the hero. |
| `coinMessage` / `rallyMessage` / `rallyReveal` / the `economy` flight beat | four staged FTU celebration windows (§10.2) | **Retired as pieces.** The RP block is a standing region painted from t=0; the coin gain is painted at its final value from t=0. `ResultsParts.primerMessages`, `Parts.econPrimer`'s presenter use, `barHeld`, `barCounting`, `gainHeld`, `gainFlying`, `primedStatic` and the `PrimedStatic` / `PrimedStaticCompact` forms all retire with them. |
| `TYPE.barLabel` (12) | the RP caption, the tier chip **and** the in-track `+N` — three jobs, one 12 px size | Retired. Replaced by four named roles (§A.2). |

**AMENDMENT A46 (2026-08-01, game-designer ruling `design-finish-reward-2026-08-01` §2.2, §5.1,
§5.2): THE RESULTS SURFACE DECLARES SEVEN REGIONS, AND THE RALLY-POINTS BAND IS ONE OF THEM
UNCONDITIONALLY.** `FieldHead`, `Sponsors`, `BogeyCallout`, `Bait` and `Tease` leave the region list
(the last two survive as commentary *content*). `RallyPoints` loses its `opts.roomy` gate (A28's
"two homes", A39's width-alone re-cut) and its `mayDrop` flag entirely: the piece has **one** home,
it is present on every arrangement including the narrowest, and it never rotates. `opts.roomy` is
deleted from `ResultsScreen.Options` — after this amendment nothing on this surface consumes a size
class except `opts.ctasBelow` (A42, untouched). This supersedes A28(1) and A39(1) in full; A28(2)'s
*read* findings (the caption/tier row, the house glyph, the 20 px track) survive and are extended by
A48.

### A.1.1 The seven regions

`rank` is adaptation priority (1 = most important, dropped last). Every floor is content-expressed.

| # | Region | Group | Rank | Forms (richest → minimum-viable) | Floor | mayScroll | mayDrop | Scheduled iff (a **t=0 latched** fact) |
|---|---|---|---|---|---|---|---|---|
| R2 | `Ctas` | `next` (trail lane) | **1** | `CtaRow` → `CtaColumn` (`ViewThatFits`), then `CtaStack` | `{ targets = 2 }` | no | **no** | `not ctasBelow` |
| R2b | `CtasBottom` | `bottomBar` (span below) | **1** | `CtaBottomRow` — one candidate | `{ targets = 2 }` | no | **no** | `ctasBelow` |
| R3 | `Field` | `field` (main lane) | **2** | the list → the same list scrolling | **`{ lines = 4 }`** (was 2 — see A46 note below) | **YES — the only one** | no | always |
| R5 | `HeroBand` | `ceremony` (lead lane) | **3** | `HeroFull` (plate at the slam cap) → `HeroChip` (one line) | `{ lines = 1 }` | no | no | `heroVisible` (A11's tally fact) |
| **R14** | **`RallyPoints`** | `ceremony` | **4** | **`RallyBlock` — ONE form (§A.3)** | `{ lines = 3 }` | no | **no** | **always** |
| R6 | `Commentary` (was `CelebrationSlot`) | `ceremony` | **5** | `CommentaryFull` → `CommentaryCompact` | `{ targets = 1 }` | no | **yes** | `commentaryScheduled` |
| R13 | `Recap` | `caption` (span above) | **6** | two lines → one line | `{ lines = 1 }` | no | yes | `hasRecap` (sponsor/observer chair only) |

Masthead (`BankChip`, `Countdown`) and `Skip` are **not** `UI.Region`s and do not change class —
they stay the `MastheadStrip` ZStack and the `Anchor` overlay for the reasons §S16.16-pre gives.

**Why the `Field` floor rises to 4 rows.** E7: landscape shows 5 of 8 finishers with the bottom row
cut. A 2-line floor lets the composition call a 2-row field legal, so a landscape phone can resolve
`threeLane` with a field that cannot show the podium. Four rows is the smallest field that answers
"who beat me" without a scroll gesture; below it the arrangement is illegal and the composition steps
down. On the measured landscape phone (844×390) the body is ~300 px tall and 4 rows is 144 px, so
`threeLane` stays legal with room for 7 rows visible and the 8th reached by the one legal scroll.

### A.1.2 What each arrangement resolves to

**`threeLane`** — landscape phone, handheld, tablet, desktop, ten-foot.

```
┌ MastheadStrip ────────────────────────────────────────────────────────────┐
│ [◍ 1917 +25]                   Next race in: 3                    [⏩ Skip]│   masthead (ZStack)
├───────────────────────────────────────────────────────────────────────────┤
│ Recap — the sponsor's drama tally, full width                             │   span "above"  (sponsor chair only)
├────────────────┬────────────────────────────────────┬─────────────────────┤
│  CEREMONY      │  FIELD (fill, weight 1)            │  NEXT               │
│  ┌──────────┐  │  1st ● Josh                        │                     │
│  │   1st!   │  │  2nd ● Bolt                        │   [ Race Again ]    │
│  └──────────┘  │  3rd ● Wrenchy                     │   [ Sponsor a Race ]│
│  Rally Points  │  4th ● Bruno                       │                     │
│      ⌂ Qualifier│ 5th ● Razz                        │                     │
│  ▰▰▰▰▱▱  +100  │  … (scrolls)                       │                     │
│  They raise…   │                                    │                     │
│  ┌──────────┐  │                                    │                     │
│  │commentary│  │                                    │                     │
│  └──────────┘  │                                    │                     │
└────────────────┴────────────────────────────────────┴─────────────────────┘
```

- lead lane (`ceremony`, hug, `place = "center"`): `HeroBand` → `RallyPoints` → `Commentary`,
  in that order, `gap = "s"`. Lane width = `metrics.laneMeasure` = **240**.
- main lane (`field`, fill weight 1, `minWidth = metrics.fieldLaneMin` = 235): `Field` only.
- trail lane (`next`, hug, `place = 0.66`): `Ctas` only — **empty when `ctasBelow`**, in which case
  rule 9 collapses it at the first solve and the field takes its width. That collapse is a t=0 fact
  and is therefore legal under A47.
- span below: `CtasBottom` when `ctasBelow`.

**`twoLane`** — small landscape phone (667×375), a windowed pane, a split-view tablet. `field` takes
the lead lane at full height; `ceremony` and `next` share the trail lane as a column, ceremony on top.
The RP block is the same single form at the trail lane's width (≥ 185 px, §A.3.4).

**`column`** — portrait phone, tablet portrait, any tall offer. Top → bottom:
masthead · **Recap** · **HeroBand** · **RallyPoints** · **Commentary** · **the Field, filling** ·
**Ctas** in the thumb arc. The lane wrappers are the same tree in both axes (§S16.6, unchanged).

**Per-region consequences of the two rulings, stated per arrangement so there is nothing to infer:**

| Region | `threeLane` | `twoLane` | `column` |
|---|---|---|---|
| `RallyPoints` | lead lane, 240 px wide, under the hero. **Never dropped, never rotated, never gated on a size class.** | trail lane, ≥ 185 px. Same. | full column width. Same. |
| `Commentary` | lead lane, fixed 240 × 76 box, **reserved for the screen's life** when scheduled; absent entirely when not | same | same, under the RP block |
| `HeroBand` | lead lane, `HeroFull` (160 × 56 plate inside the 240 lane) | `HeroFull`; `HeroChip` only if the trail lane cannot afford 56 px | `HeroFull` |
| `Field` | main lane, scrolls past row 7 | lead lane, full height | fills the column; scrolls only when 8 rows exceed the remaining height |
| `Ctas` / `CtasBottom` | exactly one live, per `ctasBelow` | side home | side home (phone) — `ViewThatFits` picks `CtaRow` |
| `Recap` | span above, sponsor chair only | same | same |

**The sticker row's absence changes no geometry anywhere**, because `FieldHead` is deleted rather than
emptied: there is no zero-measure node left where it stood, so no lane re-solves when it is not there.

---

## A.2 The type scale

### A.2.1 The ramp after this change

`44 · 34 · 24 · 20 · 18 · 16 · 14 · 12`. Every entry below is a step on it; nothing is invented
between steps, so the hierarchy stays readable as a hierarchy rather than as twelve nearly-equal sizes.

| `ResultsParts.TYPE` key | Was | **Now** | Why |
|---|---|---|---|
| `slam` | 44 | **44** | unchanged — the hero owns the top of the ramp on race 1 and race 100 (§2.2) |
| **`rpDelta`** | — (`barLabel` 12) | **34** | **New role.** §6.3: "the delta numeral is the second-largest thing on the screen after the hero." 34 is the ramp step below the slam; it is **2.83×** the size it was and reads at arm's length on a phone (34 px ≈ 24 px cap height ≈ 2.3° of visual angle at 45 cm — well above the ~0.3° acuity floor, and above the 0.6° at which a numeral stops being *glanceable*). Not 44: a delta equal to the hero has no hierarchy, and §2.2 says the hero is "never displaced." |
| **`rpCaption`** | — (`barLabel` 12) | **14** | **New role.** "Rally Points" is the label of the only reward the screen narrates; at 12 it was the smallest type on the surface, which is what the director read as "a 12 px caption." |
| **`rpTier`** | — (`barLabel` 12) | **14** | **New role.** The tier chip (`⌂ Qualifier`) is ambient (it carries the season-scale truth, §6.2) so it stays well under the delta, but it matches the caption it shares a row with — two labels at two sizes on one row reads as a mistake. Legacy's house glyph stays (A28(2)). |
| **`rpClause`** | — | **14** | **New role.** The teaching clause. Same size as the caption it sits under: it is a *note on* the line, not a headline. Derived down per locale (§A.7). |
| `barLabel` | 12 | **retired** | It was carrying three unrelated jobs at one size. One fact, one role. |
| `coinTotal` | 16 | **18** | §A.4 |
| `coinGain` | 14 | **18** | §A.4 |
| `countdown` | 16 | **16** | unchanged size; new minimum-viable form and new suppression rule (§A.4.3, §A.6) |
| `skip` | 12 | **14** | 12 px inside a 44 px target reads as a mistake; A13's mark+word is unchanged, the chip grows past the target floor as §S16.10 already allows |
| `bait` | 13 | **14** | 13 was an off-ramp orphan (legacy needed a non-circular metric for `AutomaticSize`); this build does not, and the promo line is now commentary inside a fixed box |
| `reward` | 18 | **retired** | its only consumer was the sticker row |
| `rollCallHeader` · `seatName` · `seatMarker` · `sponsorsHeader` · `sponsorChip` · `bogey` | — | **kept, unreachable at RESULTS** | the roll-call machinery is frozen-legacy shared (A41); the entries stay pinned so the legacy consumer is untouched |
| `heroStory` 24 · `recap` 20 · `standingRank` 18 · `standingName` 20 · `payoff` 20 · `awardTitle` 18 · `awardReason` 14 · `rmRow` 18 · `streak` 14 · `tease` 16 · `cta` 22 | — | **unchanged** | the field is SUPPORT 1 and static; commentary is commentary |

### A.2.2 The delta: its role, its position, and how it derives down

**Position — in-track is now wrong, and here is the arithmetic.** The track is
`BAR_HEIGHT_PX = 20`. A 34 px glyph does not fit inside a 20 px pill, and raising the track to hold it
would make the *bar* the loudest object on the screen — which inverts §6.3 ("bars communicate
position; numbers communicate event"). The delta therefore **leaves the track and takes its own box to
the right of it**, vertically centred on the bar, right-aligned:

```
RallyPointsTrackRow  (HStack, align = "center", height = 42)
  ├─ RallyPointsBar    width = fill(1),  height = fixed(20), corner = pill
  ├─ Spacer            width = "s" (8)
  └─ RallyPointsDelta  width = fixed(RP_DELTA_BOX_W = 88), textAlign = "end", lineLimit = 1
```

- `ResultsScreen.BAR_DELTA_INSET_PX = 4` is **retired** (nothing sits inside the track any more).
- **`RP_DELTA_BOX_W = 88`.** Derived, not authored: the widest delta token is `+100` — 4 glyphs at
  Gotham Bold's ~0.58 em digit advance × 34 px = **79 px**, plus 9 px of slack for a wide-digit locale.
  The box is **fixed** so the bar's width is identical for `+100` and `+24`: a delta that resized its
  own box would move the bar under the player's eye, which is the very defect A47 exists to kill.
  Right-alignment keeps the numerals' right edge stable across every value.
- **The delta is `accent` (255,150,60)**, the Prestige hue — never `coin` gold. Invariant 3.

**Derivation down, without clipping.** The delta text is
`Parts.fitWidthType(TYPE.rpDelta, deltaText, RP_DELTA_BOX_W, 1)` — the surface's own derivation, which
takes the 34 cap and comes down only as far as *this* string needs in *this* box. The token is
`"+"` plus at most three ASCII digits (RP per race ≤ 100 racer, ≤ 95 sponsor) and is **never
localized**, so on every supported offer it lands at 34. The floor is **`rpDeltaMin = 24`**: below
that the numeral has stopped being the second read and the region's own floor (`{ lines = 3 }`) has
already failed, which makes the arrangement illegal — the composition steps down rather than paint a
sub-24 delta. There is no path on which the delta clips, because the box is sized to the widest
possible token before any text is measured.

**AMENDMENT A48 (2026-08-01): THE RALLY-POINTS DELTA IS ITS OWN TYPE ROLE, ITS OWN BOX, AND IT LEAVES
THE TRACK.** New `TYPE` roles `rpDelta = 34`, `rpCaption = 14`, `rpTier = 14`, `rpClause = 14`;
`TYPE.barLabel` and `ResultsScreen.BAR_DELTA_INSET_PX` retire. **This is a deliberate parity break
with `SponsorResults:1500-1514`**, whose `+{n}` lives inside the track at a 12 px cap: legacy's own
composition is what the director could not read, and A15's "every size here is legacy's own" is
therefore relaxed for exactly this one channel, with 34 taken from the existing ramp rather than
invented. Everything else A15 pins is untouched.

---

## A.3 The Rally-Points block — one form, every arrangement

### A.3.1 The ruling on "one row"

§5.2 asks for a compact form that carries `Tier · bar · +N` in one row and never rotates. **A literal
single row is the wrong compact form, and the arithmetic says so.** At the block's own minimum type
sizes, a true one-row layout needs

```
⌂ Qualifier(12) 66px  +  gap 6  +  bar 60px(min)  +  gap 6  +  +N(28) box 78px   =  216 px
```

whereas the **two-line block** below needs only

```
line 1:  "Rally Points"(14) 92px + gap 8 + "⌂ Qualifier"(14) 85px            =  185 px
line 2:  bar(min 144 in a 240 lane) + gap 8 + delta box 88                   =  ≥ 160 px
                                                              binding min    =  185 px
```

The stacked block is **31 px narrower** than the "compact" row *and* it keeps the delta at 34 instead
of 28 and keeps the caption. So there is **one form**, used on `threeLane`, `twoLane` and `column`
alike — which is also the strongest possible reading of Ruling 5.3 (a region that has only one form
cannot step down, so it cannot change shape). All three facts are in one indivisible box: tier and
caption share the top line, bar and delta share the bottom line.

### A.3.2 The box

```
UI.VStack{ id = "RallyPoints", gap = "xs" (4), width = FILL, height = CONTENT }
├─ RallyPointsChipRow   HStack, height = 18, align = "center"
│    ├─ RallyPointsCaption   Text  "Rally Points"   TYPE.rpCaption 14   tint dim (180,186,200)  lineLimit 1
│    ├─ Spacer               fill
│    └─ RallyPointsTier      Text  "⌂ Qualifier"    TYPE.rpTier    14   tint accent (255,150,60) lineLimit 1
├─ RallyPointsTrackRow  HStack, height = 42, align = "center"
│    ├─ RallyPointsBar       ProgressView  value = barFraction, height = 20, corner pill, non-interactive
│    ├─ Spacer               "s" (8)
│    └─ RallyPointsDelta     Text  "+100"           TYPE.rpDelta   34   tint accent   textAlign end
│                            width = fixed(88)
└─ RallyPointsClause    When latched(clauseShown)      ← §A.7
     └─ RallyPointsClauseText  Text  "They raise your season tier."
          TYPE.rpClause 14, tint dim, textAlign start, lineLimit 2,
          height = fixed(2 × lineHeight(14) = 36)      ← reserved at TWO lines always
```

**Derived heights** (never authored; each is `ceil(textSize × 1.25)`, the surface's line box):

| | height |
|---|---|
| chip row | `ceil(14 × 1.25)` = **18** |
| track row | `max(BAR_HEIGHT_PX 20, ceil(34 × 1.25) 42)` = **42** |
| clause row | `2 × ceil(14 × 1.25)` = **36** |
| gaps | `xs` = 4, twice (taught) / once (bare) |
| **`RP_BLOCK_H_TAUGHT`** | 18 + 4 + 42 + 4 + 36 = **104** |
| **`RP_BLOCK_H_BARE`** | 18 + 4 + 42 = **64** |

The streak chip (`TYPE.streak` 14, coin hue) that used to ride this row is **dropped from the block**
— §5.2 authorises exactly this trade ("the tier chip and the streak chip fold into that row or are
dropped… dropping ambient chrome to keep a ledger fact is always the right trade") and it is a Coin
fact, which §1.3 demotes off this screen. It survives as commentary content (§A.5), where the promo
`tease` line already carries the same idea.

### A.3.3 Internal proportions

At the ceremony lane's 240 px: bar = 240 − 88 − 8 = **144 px** (60 % of the block width), delta box
88 (37 %), gap 8 (3 %). At a 288 px portrait column: bar 192 (67 %), delta 88 (31 %). The bar is
always the majority of the row and the delta always the same absolute size — so "the map got wider,
the event stayed the same size" is the read on every device, which is exactly §6.3's hierarchy.

### A.3.4 The floor

- Declared: **`floor = { lines = 3 }`** — chip line, track line, clause line. Content-expressed, so
  it moves with the theme's type scale and the player's preferred-text setting.
- Effective minimum width: **185 px**, the chip row's two labels at their 14 px roles plus one `s` gap.
  Every supported offer clears it: the narrowest arrangement (`column` on a 320 pt phone, `padding
  "m"` = 16 each side) hands the region **288 px**; `twoLane`'s trail lane and `threeLane`'s ceremony
  lane are both ≥ 240.
- `mayDrop = false` and there is exactly one form, so **there is no legal resolution of this surface
  on which the Rally-Points line is absent, shortened, or replaced.** That is Acceptance 4, made
  structural rather than tested-for.
- **If a future offer could not clear 185 px**, the *arrangement* is illegal and the composition steps
  `threeLane → twoLane → column`; the block is never the thing that gives.

---

## A.4 The coin chip

### A.4.1 Sizes and box

| Node | Was | Now |
|---|---|---|
| `CoinGlyph` (the gold disc placeholder) | 16 × 16 | **18 × 18** |
| `CoinTotal` | `TYPE.coinTotal` 16 | **18** |
| `CoinGain` | `TYPE.coinGain` 14 | **18** |
| `BankChip` padding | `"xs"` (4) | **`"s"` (8)** |
| `BankChip` gap | `"xs"` (4) | **`"xs"` (4)**, unchanged |
| tint | glyph + gain `coin` (255,205,90); total `content` | **unchanged** — invariant 3 |

Resting chip width on a 388 pt portrait: 8 + 18 + 4 + `"1917"`@18 (≈42) + 4 + `"+25"`@18 (≈31) + 8 =
**115 px**. Placement is unchanged: `alignment("start","center")` in the `MastheadStrip` ZStack — top-
leading, out of the centre, out of the ceremony lane, diagonally opposite nothing it can compete with.

### A.4.2 Why 18, and why it does not compete

18 px is **1.29×** its old size and the same role weight as a standings rank — legible at arm's length
for a 3-glyph token — while being **0.53×** the RP delta's 34. Half the size, a different hue, a
different corner of the screen, and it never moves. There is no instant at which the two `+N` tokens
are ambiguous:

| | RP delta | Coin gain |
|---|---|---|
| size | 34 | 18 |
| hue | `accent` orange | `coin` gold |
| position | ceremony lane, beside the bar | masthead, top-leading |
| motion | punches once, at the REWARD beat | **never moves** |

### A.4.3 The chip is ambient, and it is *already settled* at t=0

`gainHeld`, `gainFlying`, the DV5-3 flight and the `clock:counter` count-up all **retire** (§1.3: "No
plate, no flight, no caption, no dedicated beat"). The chip paints the **post-race total and its gain
on the first frame** — which is also ARRIVE's own contract ("the coin chip already at its new total").
This deletes the §10.1 pre-show defect by deleting the pre-show, rather than by adding a third state.

**AMENDMENT A49 (2026-08-01): THE COIN CHIP IS AMBIENT, SETTLED AT t=0, AND THE COUNTDOWN YIELDS TO
IT — NOT THE OTHER WAY ROUND.** Sizes as above. The DV5-3 reward beat (featured `+N` → flight → count-
up) and every hold state retire. **This reverses §S16.12's masthead ladder**: previously the countdown
owned the centre absolutely and the chip gave ground (`full → total-only → hidden`). After this cut
the chip carries the last earned fact left in the masthead and the countdown is pure chrome whose
*numeral* is its entire information, so on any offer where the full chip and the spelled countdown
phrase would collide, **the countdown steps to its minimum-viable form (the numeral alone) first**,
and only if that still collides does the chip drop its gain. Worked case, 320 pt portrait: chip 115 px
at the leading edge, `"Next race in: 3"`@16 ≈ 120 px centred spans 100–220 → collision; the countdown
steps to `"3"` (≈ 12 px centred) and the chip keeps `+25`. Both steps are t=0 facts (§A.5).

---

## A.5 Fixed geometry — how the composition actually achieves it

This is the hardest ask on the page, and it has one root cause and one rule.

### A.5.1 The defect class, named

Every region on this surface is built as `laneForm(id, UI.When{ condition = X, thenView = … })`.
`laneForm` is a `ZStack` with `height = CONTENT`, so when `X` is false the subtree **measures 0 × 0**
— the framework's honest "empty ⇒ absent" measure. The composition's `measure(regionId, formIndex,
availW, availH)` therefore returns a *different answer at a different time* whenever `X` is a clock
fact, and the next solve legitimately re-ranks, re-steps, or (rule 9) collapses a whole lane. That is
E2 exactly: at 3566 → 3567 the RP region's `rallyPersistent` and the slot's `celebrationLive` both
flipped, the lead lane re-measured, and three things relocated while the player was reading them.

**A region's measure is a pure function of `(offer, formIndex)`. Any condition that can change during
the screen's life and that gates a *measured node* is a geometry mutation, and there is no policy —
`reserved`, `mayDrop`, rule 9 — that can undo one.**

### A.5.2 The rule: two classes of condition, and a latch

**AMENDMENT A47 (2026-08-01, game-designer Ruling 5.3): ON THE RESULTS SURFACE A `When` MAY BE GATED
ONLY ON A t=0-LATCHED FACT. TIME DRIVES PAINT, NEVER MEASURE.**

| class | facts | may gate a measured node? |
|---|---|---|
| **Solve facts** — known at the first solve and constant for the screen's life | chair/role, `heroVisible` (A11's tally), `hasRecap`, `commentaryScheduled`, `clauseShown`, `ctasBelow`, `chipVisible`, `showGain`, `reducedMotion`, the size class | **yes** |
| **Time facts** — a function of the tail clock or of a server tick | `slotContent`, `celebrationLive`, `barHeld`, `gainFlying`, `barCounting`, the countdown numeral, elapsed | **never.** They may drive `opacity`, `tint`, `text`, and a control's `enabled` — nothing that is measured |

**The buildable primitive.** One helper, used by every region-shaping condition, and the only sanctioned
way to write one:

```lua
-- Reads a Readable ONCE, at construction, and returns a PLAIN value.
-- The name is required: it is what the resolution dump reports and what the
-- geometry-stability spec asserts against.
function ResultsScreen.latched(name: string, source: any): boolean
```

A `UI.Region`'s `children` may contain a `UI.When` **only** if its `condition` is a value produced by
`latched`. This is enforceable at construction (a `Readable` handed to a region-shaping `When` on this
surface is an authoring error), and it is the single check that makes Acceptance 3 structural.

### A.5.3 Region by region — exactly what changes

| Region | Today | After |
|---|---|---|
| `RallyPoints` | `When rallyPersistent` (reads `opts.roomy` **and** `view ~= nil`) | **no gate at all.** The region is unconditional and its single form paints unconditionally. `opts.roomy` deleted (A46) |
| `Commentary` (was `CelebrationSlot`) | host box behind `celebrationLive`; `reserved = celebrationHeld`, a live read; each piece a `When` on `slotIs(…)` | host is `UI.ZStack{ width = fixed(laneW 240), height = fixed(metrics.celebrationSlot 76) }` painted **unconditionally whenever the region is scheduled**; `reserved = latched("commentaryScheduled", …)`; award / payoff / bait / tease are **`opacity` crossfades inside a `canvasGroup`**, never `When`s. `commentaryScheduled` is `hasAward or hasPayoff or hasBait or hasTease` — all round facts, all known at t=0 |
| `HeroBand` | `When heroVisible`, plus §10.4's "the HeroBand *yields* while a message is up" | `When latched("heroVisible", …)`. **The yield is deleted** (game-designer Ruling 4.2 — the hero never yields, and there are no messages left to yield to). `heroContent = "none"` no longer takes the band down; it is ignored at RESULTS |
| `Field` | rows final at t=0 (A41); `RmAwardRow` / `RmPayoffRow` gated on `reducedMotionAndAward` etc. | unchanged in kind; the two RM rows are gated on `latched("reducedMotion", …)` and their content is fixed. The award/payoff RM rows now also carry bait/tease, since those left the region list |
| `Recap` | `When isRecap` | `When latched("hasRecap", …)` |
| `BankChip` / `CoinGain` | `When chipVisible` / `When showGain` — both true from t=0 in practice but declared reactive | both latched. The countdown's own step-down (A49) is latched too |
| `Countdown` | `width = CONTENT`, text changes every second | **`width = fixed(countdownBoxW)`**, `textAlign = "center"`, `lineLimit = 1`. `countdownBoxW` = the measure of the longest countdown string in the active locale at 16 px, computed once. A `CONTENT`-width node in a centred ZStack re-centres on every tick, which is a 1–8 px horizontal twitch once a second for the whole tail — invisible in a screenshot and exactly the kind of thing that makes a screen feel unsettled |
| `Ctas` / `CtasBottom` | `ViewThatFits` + `ctasAside` / `ctasBelow` | unchanged. Both gates are size-class facts; `ViewThatFits` chooses against a box that no longer changes, so its choice is itself a t=0 fact |
| `Skip` | `enabled = skipEnabled` | unchanged — a control *state*, not a presence. §S16.10's `disabled-with-reason` is correct and stays |

### A.5.4 What this does to rule 9 and to `laneForm`

- **`laneForm`'s "empty ⇒ absent" measure is kept, unchanged.** It is the framework being honest. The
  guarantee is now upstream of it: no region's chosen form is ever empty *during* a screen's life, so
  the rule can only fire at the first solve — which is precisely Ruling 5.3's "if a region cannot be
  afforded, it is not scheduled; if it is scheduled, it holds its box until the screen dies."
- **Rule-9 lane collapse becomes unreachable at RESULTS on the lead lane**, because `RallyPoints` is
  unconditional and never drops. The lead lane is never empty, ever. A39's zero-motion rider
  (`celebrationHeld = celebrationLive or rallyPersistent`) is therefore **deleted as unnecessary** —
  it was a patch for a lane that could empty, and the lane can no longer empty. DV6-2(a)'s "quiet
  round collapses the lane" resolution is superseded on every arrangement, not just roomy ones.
- **Rule 9 remains reachable and correct on the trail lane**, where `ctasBelow` empties `Ctas` — a
  t=0 fact, so the collapse happens at the first solve and never again. The A42 two-column middle is
  untouched.
- **An orientation change is exempt.** Ruling 5.3 is a rule about *time*, not about the *offer*: a
  rotation or a window resize is a re-solve the player caused, and §S16.3 rule 8 (re-solve, never
  rebuild: no unmount, no lost scroll offset, no lost focus) already governs it. The spec's assertion
  is "identical resolution at a fixed offer, sampled across the whole tail" — not "identical
  resolution across offers."

### A.5.5 How the build proves it

1. Solve at t=0, capture the full resolution dump (arrangement, per-region form index, every lane and
   region rect, `collapsedLanes`, `fallback`).
2. Advance the tail clock and re-solve every **0.25 s** to the end of the longest window
   (`primerResultsTime`), on every pinned device row, both chairs, both profiles, primed and unprimed,
   reduced-motion and not, and in the ~1.4× locale fixture.
3. Assert the dump is **byte-identical** to the t=0 dump at every sample.
4. **Mutation:** restore one time-fact `When` (`rallyPersistent` is the cheapest) and prove the
   assertion bites at the sample where the schedule flips. A mutation that does not bite means the
   sampler is not looking at the geometry.

---

## A.6 The beat sheet, as a motion spec

Motion classes are LuauUI's registry names (`GameStudio/ui/LuauUI/src/motion/classes.luau`):
`container` (ζ 1.0 / 0.35 s) · `object` (ζ 1.0 / 0.28 s) · `reward` (ζ 0.7 / 0.18 s — the only
under-damped class that ships) · `decay`. No call site states raw spring params.

### A.6.1 Steady state — 5.0 s

| t | Beat | The ONE element that moves | Motion | Everything else |
|---|---|---|---|---|
| 0.00–0.30 | **ARRIVE** | the whole surface, as one group (`ResultsRoot` `canvasGroup`) | enter `materialize`, `container` | nothing. Field final, coin chip at its new total, every box at final geometry, race HUD gone |
| 0.30–1.20 | **PLACE** | `SlamPlate` + `HeroLine`: scale 0.86 → 1.00, opacity 0 → 1 | **`reward`** — the surface's one earned overshoot | nothing |
| 1.20–1.32 | *(REWARD, part 1)* | `Countdown` opacity 1 → 0 | `fast` fade (§7.4's suppression) | nothing |
| 1.32–1.52 | **REWARD**, punch | `RallyPointsDelta`: scale 0.70 → 1.00, opacity 0 → 1 | **`reward`** | nothing |
| 1.52–2.60 | **REWARD**, fill | `RallyPointsBar` value `fillFrom → fillTo` | **`object`**, 1.05 s | nothing |
| 2.60–2.72 | *(REST opens)* | `Countdown` opacity 0 → 1 | `fast` fade | nothing |
| 2.72–5.00 | **REST** | at most the `Commentary` box's crossfade (award → payoff → bait → tease, one at a time) | `fast` opacity crossfade inside the fixed box | nothing |

**The invariant, stated so a sampler can hold it:** at any instant sampled at ≤ 0.25 s, **exactly one
node subtree has a non-zero animation velocity.** The delta punch and the bar fill are *sequential*,
not simultaneous — they are one element's two-part statement, which is what §7.1's "`+100` punches;
the bar runs underneath it" describes, played in order rather than together.

`TailTuning.results.barFillS` **1.6 → 1.05** so the fill lands inside the 1.4 s REWARD beat. Feel-class
key, ±30 % tunable without re-gating. `econStartS`, `coinTickS`, `streakFoldS`, `payoffStartS`,
`payoffHoldS`, `slamHomeS`, `slamHomeDurS` and `tierUp*` are **retired** with the beats they timed.

### A.6.2 FTU — 7.5 s, the same five beats

Identical, with **REWARD held 1.20 → 4.90** (3.70 s instead of 1.40 s) and REST 4.90 → 7.50. The
motion inside REWARD is unchanged and finishes at 2.60 exactly as in steady state; **the extra 2.30 s
is dwell, not animation.** Because geometry is fixed, the clause is painted from t=0 rather than
appearing at the REWARD beat — so §7.2's "nothing new appears, one line grew" becomes the stronger
"nothing new appears at all", and the 2.30 s is pure read time at the surface's own 0.3 s/word rate
(`They raise your season tier.` = 5 words = 1.5 s floor; the surplus is the designer's margin).

### A.6.3 Reduced motion

Every spring is placed at its terminus on the frame it is armed; the surface enters with a fade
instead of `materialize`; the delta is at full scale and the bar at `fillTo` on frame 1; the
`Commentary` box shows its **first** scheduled piece statically for the whole tail, and the remaining
pieces render as static appended rows at the end of the field's scroll (`TYPE.rmRow` 18) exactly as
they do today. **No branch is needed in the presenter** — every animated value here is decorative, so
the framework's reduced-motion policy places each at its terminus. `simultaneous` no longer implies a
different layout, because there is no longer a rotating layout to differ from.

### A.6.4 Skip

Skip = skip-all, one gate behind the chip, the tap-catcher and the `SkipCelebration` action —
unchanged. It lands **the same settled state**: hero at rest, delta at 34 full opacity, bar at
`fillTo`, countdown restored, the `Commentary` box on its last scheduled piece, nothing airborne. The
CTAs are hit-testable at t = 0 in both passes and are never behind a ceremony.

### A.6.5 Sound / haptics

No new events. The existing named hooks fire on the beat boundaries they already fire on:
`ui.results.arrive` (0.00), `ui.results.place` (0.30), `ui.results.reward` (1.32 — moved from the
retired `economy` window to the delta punch, same event name). The retired coin flight's event is
**not** re-homed: it announced a beat that no longer exists.

**AMENDMENT A50 (2026-08-01): THE RESULTS TAIL IS A FIVE-BEAT SCORE OF 5.0 s / 7.5 s WITH EXACTLY ONE
MOVING ELEMENT.** As tabled above. `barFillS` 1.6 → 1.05; the coin-flight, count-up, streak-fold,
slam-fly-home and tier-up beats retire. `MatchTuning.primerResultsTime` **16 → 8** so the server's
FTU window matches the 7.5 s score with 0.5 s of slack (flagged for the producer: it is a `gate`-class
constant). The `payoff` profile's `resultsTime = 7` is left alone — the extra 2 s is REST tail, which
is the knob §7.1 nominates if the director finds the screen long.

---

## A.7 The teaching clause

**Copy:** `They raise your season tier.` — `TailCopy`, new key `resultsRallyClause`. The ratified pair's
second sentence ("You never spend them") is dropped per §8: it is half of a contrast whose other term
is no longer on this screen. `econPrimerCoins` / `econPrimerCoinsShort` **must not render on this
surface** (§1.2) — and per Acceptance 8 the build carries a test that greps the rendered copy for any
Coin-purchase claim while `CoinLedger.spend` has no production caller.

**Where it sits.** Row 3 of the RP block (§A.3.2) — directly under the bar and the delta it explains,
inside the same region, sharing the same left edge as the `Rally Points` caption. It is not a separate
region, it has no separate box, and it can never be dropped independently of the thing it describes.

**Type.** `TYPE.rpClause` = 14, `dim` (180,186,200), `textAlign = "start"`, `lineLimit = 2`. Size
derives with `Parts.fitWidthType(TYPE.rpClause, clauseText, blockW, 2)`, floored at **11**.

**The reserved box.** `height = fixed(2 × ceil(14 × 1.25)) = 36` — **always two lines**, whether the
active locale wraps to one or two. English lands on one line (28 chars ≈ 196 px at 14 px in a 240 px
lane) and the second line is empty space that nothing else may claim. That is deliberate: it is what
makes a locale change, a preferred-text change and a re-solve all produce the same block height.

**German-class behaviour.** `Sie erhöhen deine Saisonstufe.` ≈ 29 chars ≈ 203 px → one line in the
240 lane. At the ~1.4× fixture (≈ 41 chars ≈ 287 px) it wraps to **two lines** and still fits the
reserve. The pathological case is a single unbreakable compound: at 14 px a 34-character compound is
238 px and just fits the 240 lane; anything longer derives down toward the 11 px floor rather than
clipping or widening the block. **It never truncates and the box is never sized to the English.**

**Retirement, and why nothing moves.** The clause is scheduled iff
`latched("clauseShown", seasonRP_preRace < RallyPoints.SEGMENT)`.

- **Pre-race**, not post-race. `seasonRP` crosses the segment boundary *during this screen's life* on
  the race that first completes a segment; reading it live would retire the clause mid-screen, which
  is exactly the rotation Ruling 5.1 forbids. Reading the pre-race value means the clause is still up
  on the race where the bar visibly completes — the beat §4.3 describes as "the words go away on the
  same beat that the thing the words promised finally happens" — and is gone from the **next** screen.
- **Zero new persistence.** Derived from a value the client already holds. No flag, no migration, no
  rejoin edge case. `hasBankedFirstRace` / `hasBankedFirstSponsorRound` keep their settle-gate job and
  gate no copy (§4.3 corollary).
- **When it is retired**, the RP block is 64 px instead of 104 px and the field lane absorbs the 40 px.
  That is a *different screen*, not a change *within* a screen: nothing animates, nothing relocates
  under a thumb, and the veteran has simply never seen the clause.
- `RallyPoints.SEGMENT` = **500 RP** is the game designer's recommendation and is **flagged as an
  economy-designer call** (§9.2). The presenter reads it from `RallyPoints`, never a literal, and the
  bar's re-denomination itself (§6.2) is a client-side re-derivation of `seasonRP` that lands upstream
  of this spec in `ResultsChoreoModel.bar.fillFrom/fillTo`.

---

## A.8 Clearing the race HUD at the finish

### A.8.1 The root cause — a one-line regression in the LuauUI port

`client/LuauUISponsor/init.luau:2338` computes the engaged-state fan-out as:

```lua
local sponsoring = … self._isSponsor:get() == true
local driving = not sponsoring          -- ← the defect
…
for _, name in { "raceHud", "itemFx", "itemOutcomeFx" } do
    sibling:setVisible(driving)
end
```

For a **racer at RESULTS**, `sponsoring` is false, so `driving` is true, so the standings strip, the
minimap and the item pill are all told to stay visible over the finish screen. The legacy controller
does not have this bug — `SponsorController:_currentView()` (`:1379-1387`) answers `"results"` for
*any* `phase == "results"` and `_applyMode` then flips all three off. The port dropped the phase term.
This is E3 and E4 in one line, and it is a third of the clutter in all three screenshots.

The file already holds the correct fact three hundred lines above, in `hudLive`:
`use(isSponsor) and use(sig.phase) ~= "results"`.

### A.8.2 The fix

**AMENDMENT A51 (2026-08-01, evidence IMG_3565/3566/3567, game-designer §2.2 CUT rows): THE RACE HUD
CLEARS AT RESULTS.**

```lua
local atResults = … self._phaseSource:get() == "results"   -- the same sig.phase `hudLive` reads
local driving = not sponsoring and not atResults
```

- `atResults` joins the `_engagedStamp` tuple so the dedupe ("one hook call per intent") still holds
  and the flip happens exactly twice per round.
- The hook list gains **`driverStatus`** so it matches the legacy set — legacy hides the driver effect
  chips at results too (`SponsorController:1409-1411`) and the port's three-name list silently dropped
  it. Every hook stays nil-guarded.

**What goes, and how:** `RaceHud` is one `ScreenGui` carrying **both** the live standings strip and the
minimap, so both leave on a single `Enabled = false` — no per-element visibility soup. `ItemFx` takes
the item pill and its caption. `ItemOutcomeFx` takes the outcome toasts. `DriverStatusHud` takes the
effect chips. `FtueDriverFx`'s steer pill is already gone by its own state machine, but the same phase
fact should hide it defensively (it is a driving prompt and must never paint over a finish screen).

**When it returns:** on the phase edge **out of** RESULTS — i.e. at the top of INTERMISSION — which is
before the 4 s grid hold, so the standings dock is back and settled in time for A43's pre-race rival
line and the countdown. There is no fade: the surface itself enters `materialize` and exits `instant`
(§S16.13's declared asymmetry), and the HUD's return rides the same frame the results surface leaves.

**What stays on screen at the finish:** the results surface's own chrome only — the coin chip, the
countdown, Skip, the CTAs. `Next race in: N` and `Skip` in the screenshots are *results* chrome and
are correct; the standings strip, the minimap and `BUBBLE SHIELD` are not.

---

## A.9 Focus, actions, accessibility, localization (deltas only)

Everything in §S16.11 / §S16.12 / §S16.13 stands. The deltas this cut creates:

- **Focus order** is unchanged in shape — `Ctas` → `Field` (as a region) → `Skip` — and is now shorter
  because five regions left. `Recap` and `RallyPoints` are display-only and are not in the ring.
  Initial selection is still the CTA the role banner reports selected (A12/A37).
- **Cancel** = `SkipCelebration` while enabled; the chip is visibly `disabled-with-reason` when not.
- **Targets:** both CTAs, the Skip chip and the tap-catcher all resolve ≥ 44. **The RP block is not a
  target** and is not focusable — it states, it does not act.
- **Never colour-only:** the tier is a *word* behind a house glyph, not a hue; the delta carries a
  literal `+`; your own standings row carries its plate.
- **Contrast:** `dim` (180,186,200) on the results plate and `accent` (255,150,60) on the same plate
  both clear 4.5:1 at these sizes; the delta at 34 px is "large text" and clears 3:1 with margin.
- **Preferred text:** the whole cap table scales on the framework's typography scale. What wraps
  (capped): recap 2, hero line 2, clause 2, commentary 2. What truncates: standings name, seat name,
  coin total/gain, CTA label. **The RP caption and tier truncate; the delta never does** — its box is
  sized to the widest possible token before any text exists.
- **Localization worst cases added to §S16.12's table:**

| Element | Worst case | Behaviour |
|---|---|---|
| `Rally Points` caption | a long compound (`Saisonrangfortschritt`) | truncates at its half of the chip row; the tier chip is a separate box and can never be pushed |
| Tier chip | a long tier name at 1.4× | derives down to a floor of 12, then truncates; never widens the block |
| RP delta | none — digits and `+` only, never localized | fixed box, never derives, never clips |
| Clause | a 34-char unbreakable compound | derives from 14 toward the 11 floor; wraps to the reserved 2 lines; never clips, never widens |
| Countdown | a locale that spells the phrase | steps to the numeral alone **before** the coin chip drops its gain (A49) |

---

# PART B — TWO RACING-HUD OVERFLOW BUGS

## B.9 The item-slot caption (`IMG_3563`)

### B.9.1 The measured situation

`shared/HudZoneModel.drivingTopStrip` on the director's 388 × 762 portrait:

```
rowH 16.0 · standingsW 150 · standingsH 80 · mapSide 60.96 · dockW 150
dockLeftClear = 388 − 8 − 150 − 8 = 222
slotH = 762 × 0.07 = 53.34   slotW = 388 × 0.22 = 85.36   slotX = 136.64 (slid left to clear the dock)
cramped = TRUE   →   effect-timer statusW = min(388×0.26, (121.70−6)−8) = 100.88 at x = 8
```

`client/ItemFx.luau:216-230` then paints the caption as a `TextScaled` label filling the bottom **34 %**
band at **full pill width** (`Size = UDim2.fromScale(1, 0.34)`, anchored bottom-centre). The pill's
`UICorner(0.3)` resolves to `0.3 × min(w,h) = 0.3 × 53.34 = 16.0 px` of radius, which bites up to 16 px
horizontally out of the *bottom* of the pill — exactly where the caption band is. So `BUBBLE SHIELD`
is fitted edge-to-edge in a box whose corners are not there.

### B.9.2 The ruling

**Do not widen the slot.** The arithmetic kills it: the longest catalog label is
`BEACH-BALL BUMPER` (17 chars ≈ 10.5 em at Gotham Bold's ~0.62 em cap advance). For that to render at
a merely-legible 12 px it needs **126 px** of usable band, i.e. a **158 px** pill after insets — and
`fitCentered(158)` puts `poppedSlotLeft` at 41, which collapses the effect-timer zone from **100.9 px
to 27 px**. A 27 px timer is a sliver. Widening to the 130 px the dock allows still only buys a 9.6 px
caption — illegible *and* it costs the timer 45 px. **Trading a live effect timer for an illegible
word is the trade backwards.**

The standing rule settles it: *icon-first — text is a label/fallback only.* So:

**AMENDMENT A52 (2026-08-01, evidence IMG_3563): THE ITEM-SLOT CAPTION IS INSET, CAPPED, AND DROPS
BELOW ITS OWN LEGIBILITY FLOOR; THE SLOT GAINS A HEIGHT FLOOR.**

Three changes, all in `HudZoneModel.drivingTopStrip` (which returns them) and `ItemFx.makeHud` /
`layoutSlot` (which applies them). **No new zone, no width change anywhere, so no collision can be
introduced.**

1. **Slot height floor.** `slotH = clamp(vpH × 0.07, 44, 96)` (was `vpH × 0.07`). Binds only where
   `vpH < 629` — i.e. landscape phones, where the pill was 27 px tall and the *glyph* inside it 16 px.
   `slotW` is untouched, so `dockLeftClear`, `poppedSlotLeft` and `statusW` are all byte-identical on
   every viewport.
2. **Caption inset.** `captionInset = 0.3 × slotH + 2` — the pill's own corner radius plus 2 px of
   optical margin, so the outermost glyph can never sit on the curve. The caption band keeps the
   bottom 34 % of the slot height.
3. **Caption size, derived and floored** — returned by the model as `itemSlot.captionSize` (0 = do not
   draw):

```
usableW      = slotW − 2 × captionInset
captionH     = 0.34 × slotH
labelEm      = (longest label in the ACTIVE locale, in chars) × 0.62 × 1.08   -- 8% wide-glyph margin
captionSize  = min(captionH, usableW / labelEm, CAPTION_MAX = 18)
captionShown = captionSize >= CAPTION_MIN = 11
```

- The gate is evaluated against the **longest label in the catalogue**, never the current item, so the
  caption can never appear for `TURBO CAN` and vanish for `BEACH-BALL BUMPER` — a caption that comes
  and goes with the item is a moving HUD element.
- It is a **legibility floor, not a width threshold**: the rule is "if it cannot reach 11 px inside its
  own box, it is not drawn", which is the same discipline as a LuauUI region floor and survives a
  locale change, a new item with a longer name, and a device nobody has yet driven.
- `CAPTION_MAX = 18` stops a 75 px desktop pill painting a 25 px caption that out-shouts the icon.
- The **KBM `"  (E)"` suffix** is the first thing to give: if the suffixed string does not fit at
  `captionSize`, the suffix is dropped and the caption stays. (It never binds in practice — the two
  KBM-class widths land at 27 px and 19.4 px of headroom against the 18 cap.)
4. **When `captionShown` is false**, the glyph band grows from `0.60` to **`0.72`** of slot height and
   centres vertically in the pill. The icon-first trade is made *visible*: where the word is lost, the
   silhouette gets bigger.
5. **Construction change in `ItemFx`:** `label.TextScaled = false`, `label.TextSize = captionSize`,
   `TextWrapped = false`, `TextTruncate = None`, `label.Size = UDim2.new(1, −2 × captionInset, 0,
   captionH)` centred. Because `captionSize` was *derived to fit the longest label*, nothing can
   overflow and nothing needs truncating — which is also what makes it localization-safe: the box is
   never sized to the English, the *type* is sized to the locale.

### B.9.3 The resolved matrix

| Viewport | slotW × slotH | radius / inset | usableW | `captionSize` | caption | effect-timer zone |
|---|---|---|---|---|---|---|
| 388 × 762 phone portrait (the bug) | 85.4 × 53.3 | 16.0 / 18.0 | 49.4 | 4.7 | **OFF** — glyph → 38.4 px | **100.9 px, unchanged** |
| 375 × 667 small phone portrait | 82.5 × 46.7 | 14.0 / 16.0 | 50.5 | 4.8 | **OFF** | unchanged |
| 844 × 390 phone landscape | 185.7 × **44** (floored from 27.3) | 13.2 / 15.2 | 155.3 | **14.7** | ON | unchanged width; y re-centres on the taller pill |
| 1280 × 720 ROG Ally | 281.6 × 50.4 | 15.1 / 17.1 | 247.4 | **17.1** | ON | unchanged |
| 1365 × 768 Studio landscape | 300.3 × 53.8 | 16.1 / 18.1 | 264.1 | **18** (capped) | ON | unchanged |
| 1920 × 1080 desktop | 422.4 × 75.6 | 22.7 / 24.7 | 373.0 | **18** (capped) | ON | unchanged |
| 820 × 1180 iPad portrait | 180.4 × 82.6 | 24.8 / 26.8 | 126.8 | **12.0** | ON | unchanged |

**What happens to the effect-timer zone: nothing.** `statusW` is a function of `slotX` and `slotW`
only, and neither changes. The four viewports `tests/hud_zone_model.spec.luau` asserts collision-free
stay collision-free by construction; the only geometric consequence of the height floor is that on
`vpH < 629` the `statusCue` sits up to 22 px lower and the cramped-mode effect timer re-centres on the
taller pill. Add the two phone rows above to the asserted set.

### B.9.4 Flagged for the director (not decided here)

A phone-portrait player now never sees an item's **name**. That is the standing icon-first rule
applied honestly, and the reveal reel plus the icon carry the read — but it is a real information loss
on the most common device. The one cheap alternative, if the director wants the name back: announce
it **once, on grant, in the existing `statusCue` band** (already 214 px wide on this phone, already
centred in the free span, already the home of transient captions) and keep the pill icon-only
afterwards. That is a `DriverStatusHud` change, not an `ItemFx` one, and it needs a collision rule
against a simultaneous effect cue — so it is scoped as follow-up, not folded in here.

---

## B.10 The "Drag to steer" pill (`IMG_3564`)

### B.10.1 The measured root cause

`client/FtueDriverFx.luau:53-116` builds:

```
pill : AutomaticSize.X, UIPadding L/R = 24, UISizeConstraint.MaxSize = (vp.X × 0.4, h)
label: AutomaticSize.X, Size = (0,0,1,0), TextSize = 22 (FIXED), no cap, no wrap
```

`UISizeConstraint` clamps the **pill**. It does not clamp the **label**, which keeps its natural width
at a hard-coded 22 px, starts at x = 24 (the left padding) and runs straight past the clamped pill's
right edge. The M6 spec called for *"max width 40 % vpW, **TextScaled cap 22 px**"* — the
implementation shipped a fixed `TextSize` instead of a capped `TextScaled`, which is the entire defect:
a fixed type size inside a clamped box is a box sized to the English string, and the first locale or
narrow viewport that disagrees escapes it.

### B.10.2 The correct construction

**AMENDMENT A53 (2026-08-01, evidence IMG_3564): THE STEER-HINT PILL IS AN EXPLICIT BOX WITH A CAPPED
`TextScaled` LABEL. `AutomaticSize` AND `UISizeConstraint` LEAVE THIS SURFACE.** Supersedes M6_UI_SPEC
§4.3/§4.4's "40 % vpW" measure — a 40 % fraction is too narrow to hold the prompt at a readable size
on a phone and too wide to read as a prompt on a tablet, so the box takes a clamped fraction instead.

```
pill  (Frame)
  AutomaticSize   = None                      -- REMOVED
  UISizeConstraint= <deleted>                 -- nothing left for it to do
  AnchorPoint     = (0.5, 0.5)
  Position        = UDim2.fromScale(0.5, 0.64)                     -- unchanged (§4.3)
  Size            = ( clamp(vpW × 0.55, 200, 360),
                      clamp(vpH × 0.11,  56,  88) )                -- offset px, both axes
  UICorner        = UDim.new(0.5, 0)                               -- unchanged
  UIPadding       = L 20 · R 20 · T 8 · B 8                        -- symmetric (was L 24 / R 24 only)
  BackgroundColor3 = (10,10,16)  BackgroundTransparency = 0.35 when shown   -- unchanged

label (TextLabel)
  AutomaticSize   = None                      -- REMOVED
  Size            = UDim2.fromScale(1, 1)     -- fills the padded box
  TextScaled      = true
  TextWrapped     = true
  TextXAlignment  = Center     TextYAlignment = Center
  UITextSizeConstraint: MaxTextSize = 22, MinTextSize = 12
  Font/colour     = GothamMedium, (235,238,245)                    -- unchanged
```

The pill's size is a pure function of the viewport; the label can never exceed it because it *is* it;
the type auto-fits down from 22 and wraps rather than overflowing. `layoutPill()` keeps its
`ViewportSize` connection and recomputes both numbers.

### B.10.3 The resolved matrix, and what it looks like

| Viewport | pill box | text box | `Drag to steer` @22 (143 px) | German `Zum Lenken ziehen` (187 px) | ~1.4× worst case |
|---|---|---|---|---|---|
| 388 × 762 phone portrait | **213 × 84** | 173 × 68 | 1 line @ 22 | wraps to 2 lines @ 22 (55 px ≤ 68) | 2 lines @ 22, longest word 154 ≤ 173 |
| 375 × 667 small phone | **206 × 73** | 166 × 57 | 1 line @ 22 | 2 lines @ 22 (55 ≤ 57) | 2 lines @ ~21 |
| 844 × 390 phone landscape | **360 × 56** | 320 × 40 | 1 line @ 22 | 1 line @ 22 | 2 lines @ 20 |
| 820 × 1180 tablet portrait | **360 × 88** | 320 × 72 | 1 line @ 22 | 1 line @ 22 | 1–2 lines @ 22 |

**Roomy tablet vs narrow phone, stated as intent:** the **type size is the constant (22) and the plate
is what adapts.** On a tablet the pill is a calm 360 × 88 lozenge holding one comfortable line with
generous air — about 30 % of the screen width, reading as a caption laid over the road. On a narrow
phone the same 22 px sentence sits in a 213 × 84 lozenge that fills a little more than half the width
— reading as a compact instruction. The prompt has one voice everywhere; only the surface under it
changes size. That is the opposite of the shipped behaviour, where the plate was constant-ish and the
*text* escaped it.

**Corner-curve check** (the same failure mode as B.9): at 2 lines in the 388-portrait box, the text
occupies y = 14.5 … 69.5 inside an 84 px pill of radius 41.9; the cap curve's horizontal inset at
y = 14.5 is 10.2 px, well inside the 20 px padding. No glyph can sit on the curve at any supported
size.

**Unchanged:** touch-only (the `InputIdentity` gate), the show → acknowledged → gone state machine, the
0.15 s fade in/out (already reduced-motion-friendly — it is a fade, not a movement), and the
never-re-arms-this-session rule.

---

# C. Decision section — plain language, for the `UI-SPEC` gate

**The situation.** The finish screen is showing five things at once, moving three of them, and taking
one of them away on a timer. This spec makes it show three things, move one at a time, and take
nothing away. It also finds the reason the race HUD is still painted over it (one missing word in one
line of code) and fixes two places where text runs outside its box during a race.

**The three things a player will notice.**

1. **The "+100" gets much bigger** — from the size of a footnote to the second-biggest thing on the
   screen after "1st!". It also comes out of the grey bar and sits next to it, because a 34-pixel
   number does not fit inside a 20-pixel bar.
2. **Nothing on the screen ever moves or disappears once it has arrived.** Today the Rally-Points
   panel fades in, then fades out, and the list slides up to fill the hole. After this, every box is
   in its final place on the first frame and stays there until the screen goes away.
3. **The clutter goes.** The live race standings, the minimap and the power-up label all leave the
   moment you cross the line, and the "New sticker for your kart!" line is gone (the sticker itself is
   still granted and still kept — only the caption about it goes).

**What I need a ruling on.**

- **Q10 — the sponsor's recap line.** For a sponsor, the screen would show four things (round story,
  recap tally, field, Rally Points) where the budget is three. The game designer cut the sticker line
  but did not mention the recap, and you personally drew the recap as a full-width band under the
  countdown (DV5-1), so I have **kept it exactly where you drew it** and flagged it rather than cut it.
  If you want strictly three, the cheapest cut is: show the recap **only** when there is no round-story
  headline (which is already the case on a zero-drama round). Costs nothing to build either way.
- **Q11 — phones lose the power-up's name.** On a phone the item pill is 85 px wide; no font size fits
  `BEACH-BALL BUMPER` in it legibly, and making the pill wide enough would squash the boost-timer next
  to it down to a sliver. So on phones the pill becomes icon-only. If you want the name back, the cheap
  version is to flash it once, on pickup, in the caption band that already exists just below — a
  separate small job.
- **Q12 — how long the first race's screen holds.** The score is 5.0 s normally and 7.5 s on a first
  race. The server currently holds the first-race screen for **16 s**; this spec drops it to **8 s**.
  That is a big change to a number marked `gate`, so it is called out rather than assumed.
- **Q13 — the segment size.** The bar filling toward 500 points instead of 6,000 is what makes a race
  visible on it (20 % per win instead of 1.7 %). 500 is the game designer's recommendation and is an
  economy-designer call; this spec reads it from `RallyPoints` and never from a literal, so changing it
  later is a one-line change.

**What I deliberately left out.** A coin ceremony of any kind (there is nothing to spend coins on yet,
so celebrating them teaches a promise the game cannot keep); a second bar; a second explanatory
caption; any animation on the field list; and any new sound or haptic event.

---

# D. Acceptance — what the build must prove

Structural (a suite holds these):

1. **Seven regions, and only seven**, on every arrangement, both chairs. `FieldHead`, `Sponsors`,
   `BogeyCallout`, `Bait`, `Tease` are absent from the declaration, not merely unmounted.
2. **The geometry-stability sweep** of §A.5.5: identical resolution dump at 0.25 s intervals across the
   whole tail, on every device row, both chairs, both profiles, primed and unprimed, RM and not, in the
   ~1.4× locale — with the mutation proving it bites.
3. **Exactly one node subtree animating** at every 0.25 s sample from t = 0 to the end of the tail.
4. **`RallyPoints` is present, at its single form, on every legal resolution** — including the
   narrowest — and no size class reaches it (`opts.roomy` does not exist).
5. **The delta renders at 34** on every device row and derives to ≥ 24 in every locale, and its box is
   88 px wide for `+0`, `+24` and `+100` alike.
6. **The clause renders iff `seasonRP_preRace < SEGMENT`**, derived, with no persisted flag anywhere in
   the path, and its box is 2 lines tall in every locale.
7. **CTAs hit-testable at t = 0**; steady tail ≤ 5.0 s, FTU tail ≤ 7.5 s.
8. **A win moves the bar ≥ 15 % and a last place ≥ 4 %**, asserted against
   `RallyPoints.placementTable()` and `SEGMENT`, never against literals.
9. **No rendered string on this surface promises a spend path** while `CoinLedger.spend` has no
   production caller.
10. **`RaceHud` / `ItemFx` / `ItemOutcomeFx` / `DriverStatusHud` are all disabled** for the whole
    RESULTS phase and re-enabled on the INTERMISSION edge, for a racer chair and a sponsor chair.
11. **`HudZoneModel` matrix**: the seven viewport rows of §B.9.3, asserting `captionSize`,
    `captionShown`, and that `statusW` / `dockLeftClear` are unchanged from the pre-amendment values on
    every one of them.
12. **Steer pill**: at each row of §B.10.3, the label's solved text bounds are inside the padded box in
    English and in the ~1.4× fixture, and neither node carries `AutomaticSize`.

Human gates (`FEEL` / `WATCH`, not self-certifiable):

13. Portrait phone at arm's length: **is `+100` readable without leaning in?** (The director's original
    complaint; the only test of A48 that counts.)
14. Does the finish screen read as **still** — does anything appear to jump, slide or vanish?
15. Does 7.5 s on a first race feel like a reward or like a wait? If a wait, cut REST, not the clause.
16. On a phone, is the item pill's silhouette enough without its name?
