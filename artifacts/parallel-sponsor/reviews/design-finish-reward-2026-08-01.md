# Design ruling — the finish screen's reward information model

**Role:** Game Designer · **Date:** 2026-08-01 · **Trigger:** director phone session, IMG_3565/3566/3567
**Scope:** the INFORMATION MODEL and the DRAMATURGY of the race-finish screen. No pixels, no fonts, no
layout — a UI designer follows this and owns those.

`[DESIGN]: REJECT` — the current finish-screen information model. It violates §6.12's eight-year-old
corollary ("every number a kid sees has exactly one obvious meaning"), it narrates a currency the game
cannot let the player spend, it removes earned facts on a timer, and it moves five things at once so
the eye lands nowhere. Replacement model below; it is smaller than what ships today, not bigger.

---

## 0. What the evidence actually shows (before any opinion)

Read from the three screenshots, confirmed against code:

| # | Observation | Confirmed by |
|---|---|---|
| E1 | **Five things move or compete at once.** The slam plate, the coin chip's `+25`, the Rally-Points bar and its `+100`, the gold sticker caption, and the rotating slot. | all three shots |
| E2 | **The layout REFLOWS between beats.** 3566 → 3567: the Rally-Points region disappears, the sticker caption jumps ~126 px up, the field list slides ~70 px up. The eye must re-acquire everything it had already found. | 3566 vs 3567 |
| E3 | **The race HUD is still painted over the finish screen** — live standings strip (top right), minimap, `BUBBLE SHIELD` power-up label, `Next race in: N`, `Skip`. Four to five extra live elements. | 3565, 3566, 3567 |
| E4 | **The top-right standings strip duplicates the roll-call**, smaller and worse ("1st Josh / 2nd Wrenchy / 3rd Bolt" is stated twice on the same screen). | 3565 |
| E5 | **The Rally-Points region vanishes into empty space.** In 3567 there is a ~100 px void exactly where it was. The removal is driven by `isCompact` (a WIDTH class), not by any real space shortage. | `LuauUISponsor/init.luau:723-725` |
| E6 | **The gold sticker caption is the second-brightest thing on the screen** and sits directly above the field list, where it reads as a header for the list. | 3565, 3566 |
| E7 | **The roll-call is clipped in landscape** (5 of 8, bottom row cut) while portrait shows all 8. | 3565 vs 3566 |
| E8 | Landscape `Sponsor a Race` has another surface bleeding through behind it. | 3565 |

E1 and E2 are the director's complaint. Everything else is why it is worse than it needs to be.

---

## 1. What the two currencies are actually for — in player terms, and what is true TODAY

### 1.1 Chaos Coins

**Design intent (GameDesign §6.12, §8):** *"Coins buy looks."* The single cosmetic currency; the garage
is the store; Robux tops it up, never replaces it.

**Live truth: Chaos Coins have NO reachable sink. This is the real bug.**

- `CoinLedger.spend` has **zero production callers** — every call site in the repo is a test
  (`code/tests/grant_idempotency.spec.luau`). Evidence: grep of `code/src` for `\.spend\(` returns only
  `shared/CoinLedger.luau:169` (the definition itself).
- The only garage surface, `client/GaragePilotScreen.luau`, is priced at **zero** — its card states are
  `EQUIPPED / Owned / "Earn on pick"`. Nothing costs Coins.
- That surface is not even reachable: `client/init.client.luau:788` mounts it only behind
  `workspace:GetAttribute("UseLuauUIGaragePilot") == true`, described in its own header as *"a NEW
  surface with no default entry point until the Paddock lobby."*

**Ruling 1.1 — In the shipped build, the honest player-facing sentence for Chaos Coins is "a number
that goes up."** It is not a currency yet; it is a savings account with no shop attached.

**Ruling 1.2 — The FTU currently teaches a promise the game cannot keep.** The ratified primer copy is
`"Chaos Coins buy new looks for your kart."` (`FTUE_ECON_REVEAL_SPEC` §4.3). There is nothing to buy and
nowhere to buy it. A first-timer told this will go looking, find nothing, and learn that the game's
words are not reliable. **That line must not ship until a sink is reachable.** This is a stronger
failure than the legibility complaint: an unreadable true statement is a nuisance; a readable false one
is a trust cost.

**Ruling 1.3 — Coins are therefore demoted to AMBIENT on the finish screen, and their teaching moves to
the point of USE, not the point of grant.** The chip in the corner ticks up. No plate, no flight, no
caption, no dedicated beat, no `coinMessage` window. When the Paddock/garage ships, the coin total sits
next to things that cost coins and the sentence "Coins buy new looks" is taught *there*, where it is
immediately actionable and immediately true. Teaching a currency where you spend it is strictly better
teaching than teaching it where you earn it.

*(Rationale: this is not austerity. A reward the player cannot act on is not a reward; narrating it
costs the screen's whole attention budget and buys nothing.)*

### 1.2 Rally Points

**Design intent (GameDesign §6.11, §6.12):** your **score in the Chaos Cup season**. Placement-dominant,
play-only, never spendable, fills toward season tiers (Qualifier → Contender → Finalist → Chaos
Champion). This is the Prestige axis.

**Live truth: real and correct.** `shared/RallyPoints.luau` — placement table `{100, 80, 65, 52, 42, 34,
28, 24}`, sponsors on the same ladder at 0.7 × drama capped 95, no spend/purchase/multiply path exists
by construction, placement-dominance is a CI invariant.

**But the instrument is illegible**, for one structural reason: the bar's denominator is the season tier
threshold, **6,000 RP** (Contender). A win is 100 RP. **A race is 1.7 % of the bar** — roughly a 60-race
denominator painted against a one-race grain. No font size fixes that; the ratio is wrong. See §6.

**Ruling 1.4 — Rally Points is the finish screen's reward. Coins are not.** The finish screen is the
**Prestige** screen: it exists to answer "how did I do?", and RP is the numeric answer to exactly that
question. Coins are a **Collection**-axis fact and belong on the Collection surface. Sorting the two
axes onto the two surfaces they each belong to removes half the finish screen's content with zero
information loss — that is the whole solution to "too much information," and it is a rule, not a trim.

---

## 2. The budget, and the ranking

### Ruling 2.1 — Hard budget: **three content elements. Not four.**

Plus chrome (CTAs, coin chip, countdown, skip). And three inviolable constraints on top of the count:

- **2.1a — At most three numbers on screen.** Today: place, `+25`, wallet total, `+100`, bar fill,
  countdown = six.
- **2.1b — Exactly ONE thing may move at a time.** *Motion is the narrator.* When more than one thing
  moves, nothing is being said. This is the single most load-bearing ruling in this document, and it is
  what the director is actually reporting when he says "I can't tell what's going on."
- **2.1c — At most ONE element may carry information the player has never seen before.** On a first
  race that budget is spent on Rally Points. Nothing else may claim it.

### Ruling 2.2 — The ranking

| Rank | Element | Ruling |
|---|---|---|
| **HERO** | **Your placement** (`1st!`, or the sponsor role's show-result headline) | The answer to the question the player just asked, on race 1 and race 100. Exactly one hero, always this one, never displaced — including by a first-time teaching beat (see §4.2). |
| **SUPPORT 1** | **The final field** (roll-call, all 8, plain rows) | Answers "who beat me / who did I beat" — the rivalry substrate (§6.12). Glanceable, **static, never animated, never annotated**. No badges, no `+N` on the winner's row, no rings/strokes/marker bars (standing rule). |
| **SUPPORT 2** | **The Rally-Points reward line** — one line carrying tier name + bar + `+N` | The one reward this screen narrates. See §5.2 for its compact form and §6 for its magnitude. |
| AMBIENT | Coin chip (total, small `+N`, top corner) | Present, ticks, **never narrated**. §1.3. |
| AMBIENT | `Race Again` / `Sponsor a Race` | Load-bearing, always present, **reachable from frame 1**, never rotated, never gated behind a ceremony. |
| AMBIENT | Countdown, Skip | Chrome. See §7.4 for the one FTU exception. |
| **CUT** | "New sticker for your kart!" | §3. |
| **CUT** | The live-race standings strip (top right) | E3/E4 — duplicates SUPPORT 1, smaller and worse. The race HUD must clear at the finish. |
| **CUT** | The minimap and the power-up label, post-finish | E3 — race instruments on a non-race screen. |
| **CUT** | Any second currency line, any second bar, any second explanatory caption | §1.3, 2.1a. |
| **CUT** | The `coinMessage` and `rallyMessage` full-screen ceremony windows | §7 — replaced by a single reward beat that never displaces the hero. |

**Ruling 2.3 — Commentary is a separate class from ledger.** Award callouts and rivalry payoff lines are
*commentary*: optional, rotatable, droppable. Place / delta / totals / field are *ledger*: stated once,
stated permanently. §5 turns this into the rotation rule. Commentary gets **one lane** and it is the
only lane that ever changes content.

---

## 3. "New sticker for your kart!" — ruling with evidence

### The evidence

The grant is **real**, not vestigial:

- `server/FTUEReward.luau` — `STARTER_STICKER = "firstSmileSticker"`, DataStore-backed, idempotent,
  survives reconnect.
- `server/SponsorFtue.luau:217-232` — `applyRewardDecal` puts a real `Decal` on `Body/Hull`.
- `server/SponsorFtue.luau:259-266` — `applyOwnedRewards` re-applies it to a rebuilt kart on rejoin, so
  "you keep it" is honoured.

But the **object is not legible**, for four independent reasons:

1. **It is not art.** `REWARD_DECAL_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"` — an
   engine particle sprite, tinted gold, chosen (per its own comment) because it *"always loads, no
   upload."* That is a placeholder standing in for a cosmetic, not a cosmetic.
2. **It is on `Enum.NormalId.Top`** — the roof of the hull. It is not on a face the player looks at.
3. **It is not visible in any of the three screenshots**, in two of which the player's kart is large and
   centred and unobstructed.
4. **There is nowhere to go and look at it.** No reachable garage (§1.1).

And the *line* is actively harmful: it fires only on a 1st-place FTU finish, so it lands on the same
screen as the hero and competes with it (E6); it is gold, which is the loudest colour on the surface;
and it sits above the field list where it reads as that list's header.

### Ruling 3.1 — **CUT the line from the finish screen. KEEP the grant.**

Never-revoke (§8) is absolute; the player keeps what they were given. But a caption that announces an
invisible object in an unreachable place is not an unlock moment — it is a rumour.

### Ruling 3.2 — The first-win cosmetic is owed a real moment, and its home is the KART, not the screen.

The finish camera is already on the player's kart in every screenshot. The correct beat costs **zero UI
budget**: the sticker lands on the car, in world, with a pop and a spark, and the screen says nothing at
all. "The game put a thing on MY car" is the emotion §7 asks for, and a caption can never deliver it —
only the object can. Preconditions, both **separate follow-up work, not this task**:

- **Art:** an authored decal (Rascal Rally sticker language — see `ArtStyle` "UI should feel like
  stickers, signs, and carnival graphics"), on a face the chase camera and the finish camera can see.
- **A place to see it again:** the Paddock/garage. Until then the reveal is a one-shot with no home.

**Until both exist, the finish screen says nothing about the sticker.** If the director wants the beat
back sooner, the art is the cheap half and should be scheduled first.

---

## 4. FTU vs veteran — ONE structure, and the exact rule for when teaching stops

### Ruling 4.1 — There is one screen. Teaching is a **clause**, not a **stage**.

The current v2 design adds four full-screen ceremony windows on the first race
(`coinMessage → economy → rallyMessage → rallyReveal`, 14.1 s) and then a completely different, faster
screen forever after. That is two screens. Two screens means the veteran never builds a habit on the
one the beginner learned, and it means the teaching version was never pressure-tested by the people who
see the screen most.

**The structure is identical on race 1 and race 100.** The SUPPORT-2 reward line has two registers:

- **Taught:** `Rally Points  +100` · *"They raise your season tier."*
- **Bare:** `Rally Points  +100`

Same node, same box, same position, one extra clause. Nothing appears, disappears, or moves between the
two registers except that one sentence — so the beginner and the veteran are literally looking at the
same screen, and the beginner grows out of it rather than graduating off it.

### Ruling 4.2 — Teaching never displaces the hero.

`FTUE_ECON_REVEAL_SPEC` §10.4 has the HeroBand *yield* — the placement slam vanishes for 3 s so a
caption can be big. **Reject.** On the one race the game guarantees the player wins, taking away "1st!"
to show a sentence about a score is trading the emotion for the explanation. The hero holds; the clause
is a clause.

### Ruling 4.3 — The stop rule: **the clause retires when the player has SEEN the thing it describes
actually happen.**

Not "once" (once is not teaching — a seven-year-old reads it and it is gone). Not a persisted
seen-it-flag (that retires on exposure, not on comprehension). Not "forever" (that is noise by race 10).

> **The clause is shown while the player's season Rally Points are below one full bar segment
> (§6.2: 500 RP). It is never shown again once they are above it.**

Properties, all deliberate:

- **It teaches for ~5 races** at 100 RP/win, ~10-15 at back-of-pack rates — i.e. it teaches *longer for
  the player who is doing worse and needs it more*, and retires fastest for the player who obviously
  gets it.
- **It retires at exactly the moment the bar visibly completes for the first time.** The words go away
  on the same beat that the thing the words promised finally happens on screen. That is the textbook
  definition of teaching having worked.
- **Zero new persistence.** It is derived from `seasonRP`, which is already published to the client.
  No new flag, no new attribute, no migration, no rejoin edge case, no farm surface, no
  veteran-seeding problem. (Contrast: the shipped `hasBankedFirstRace` pair cost a BLOCKER, a MAJOR, and
  a migration seed — §B9/§B10/§B12 — because a caption was welded to a money gate.)
- **It survives a season rollover honestly:** carryover is `min(20 % × last season, 3000)`, so a
  returning veteran is above 500 and never re-taught, while a genuinely new player always is.

**Corollary — the `hasBankedFirstRace` / `hasBankedFirstSponsorRound` flags stay** for the thing they
were actually right for: gating the FTU race's *settle* so the authored win pays once and can never be
farmed (§3.2, §B9). They no longer gate a caption. One fact, one job.

### Ruling 4.4 — Coins get no clause on this screen at all. §1.3.

---

## 5. The rotation problem

### Ruling 5.1 — **Time-rotation of earned information is never acceptable. Ever.**

The rule, stated so it is testable:

> **A fact the player EARNED is stated once and stays stated for the life of the screen.
> Only COMMENTARY may rotate.**

Ledger (never rotates, never drops): placement, the Rally-Points delta and bar, the field, the coin
total. Commentary (may rotate, may drop): award callouts, rivalry payoff lines, flavour.

The failure in E5 is worse than "information was rotated": it was rotated **out of a screen that had
visible empty space**, because the trigger is a width class (`isCompact`) standing in for "is there
room." A width class cannot answer a height question. A portrait phone has the least width and the most
height on the whole device matrix, and it is the device where the reward disappeared.

### Ruling 5.2 — **Collapse, don't rotate.** The compact form is ONE ROW.

When space is genuinely tight, the reward line collapses to a single row carrying all three facts:

```
Qualifier   ▰▰▰▱▱▱▱▱▱▱   +100
```

Tier name · bar · delta. One row, ~one line tall, fits every screen in the matrix including the
narrowest, and **never rotates, never drops, never moves.** The tier chip and the streak chip fold into
that row or are dropped — they are ambient, and dropping ambient chrome to keep a ledger fact is always
the right trade. (Contrast §4.5 of the shipped spec, which drops the *tier* to make room for two 12 px
captions; that is the trade backwards.)

### Ruling 5.3 — **The screen's geometry is fixed for its lifetime.**

Every region reserves its box at t = 0 and never appears, disappears, grows, or moves. Content inside a
region may change; the region may not. This is what kills E2 — the 3566 → 3567 jump where three
separate things relocated while the player was reading them — and it is a stronger and simpler rule
than any per-region `mayDrop` policy. **If a region cannot be afforded, it is not scheduled; if it is
scheduled, it holds its box until the screen dies.**

---

## 6. The reward magnitude problem

The director cannot read `+25` or `+100`, and neither feels like a reward. Three separate design
faults, one of which is not a design fault at all.

### Ruling 6.1 — `+25` Coins: the problem is not the size, it is the absence of a sink. §1.

A number is a reward when it buys something. 25, 250, or 2,500 all feel identical when the answer to
"what can I do with this?" is "nothing." **Do not retune the Coin faucet to compensate.** Demote to
ambient (§1.3) and build the sink. The faucet values (25 / 15 / 8 + the streak ladder) are already
tuned against a 150–300 Coin small cosmetic — that is ~8 wins for a thing you want, which is a good
first-session curve *the moment there is a thing to want.*

**Follow-up work, flagged, not specced here:** the smallest honest Coin sink — a reachable garage with
three or four cosmetics priced 150–300. This is the highest-value item on this whole page and it is not
a finish-screen task.

### Ruling 6.2 — `+100` Rally Points: **re-denominate the bar. Do not retune the economy.**

The bar today runs to the tier threshold, 6,000 RP. A race is 1.7 % of it. That instrument cannot
show a race, so it shows nothing, on every race forever — this is not an FTU problem, it is the shipped
steady state. The spec already records this as unfixable-in-the-renderer (§4.6); it is fixable in the
*denominator*.

> **The bar fills toward the next 500-RP segment within the current tier, not toward the tier
> threshold. The tier name stays as the bar's label.**

- A win moves the bar **20 %**. A last-place finish moves it **~5 %**. Both are visible motion, on every
  race, for every player, forever.
- The bar completes roughly **once per session** (5 races), which gives the session macro-loop the
  payoff beat it currently does not have — a thing that finishes while you are playing.
- **This is a pure client-side re-derivation of `seasonRP`. No economy number changes, no new server
  field, no new faucet, no reward attaches to a segment.** §6.11's ladder integrity is untouched: RP
  still accrues the same, tiers are still the same thresholds, nothing purchasable multiplies anything.
- The tier chip (`Qualifier`) keeps carrying the season-scale truth, so the long horizon is not lost —
  it is just no longer the thing being asked to render a single race.

**Segment size is an economy-designer call**; 500 is my recommendation and my worked example (100 RP
win = 20 %; the 24-RP back marker = 4.8 %; ~5 races per segment; 12 segments to Contender). Flag it.

### Ruling 6.3 — **The numeral is the reward; the bar is the map.**

Even at 20 %, the thing the eye should land on is `+100`, not the bar's motion. Bars communicate
*position*; numbers communicate *event*. The delta numeral is the second-largest thing on the screen
after the hero, it punches, and the bar runs underneath it as context. This also makes the reward
readable when the delta is genuinely small, and it is the one place the "+N" must never be a 12 px
label tucked inside a track (3565/3566).

### Ruling 6.4 — Do **not** grant a bigger first race.

The shipped answer (authored win settles once for 25 Coins / 100 RP) is correct and stays. A
special first-race payout teaches *the game hands out money*; the normal win payout teaches *racing
pays*, which is the loop we need understood. The first race should feel like a reward because it is
**legible**, not because it is inflated.

### Ruling 6.5 — Sponsor role: a zero-drama first round shows `+0` under a line explaining a bar.

Carried, unresolved, and now more visible because RP is the hero reward (§1.4). Two honest options, both
economy-designer calls: a small first-round RP floor (mirrors the existing 8-Coin floor), or the
observer FTUE's authored beats guaranteeing non-zero drama. **Flagged, not decided here.** In the
meantime the clause is written as a rule ("They raise your season tier"), not a report, so it stays true
at `+0` — keep it that way.

---

## 7. The beat sheets

Two principles govern both: **one moving thing at a time** (2.1b), and **the CTAs are reachable from
frame 1** — a ceremony never holds the exit hostage.

### 7.1 Steady state — **5.0 s**, three beats, two eye-moves

| t | Beat | What it says | Where the eye is | What else moves |
|---|---|---|---|---|
| 0.0–0.3 | **ARRIVE** | Screen lands with the field already final, the coin chip already at its new total, every box at final geometry. Race HUD is gone. | settling | nothing |
| 0.3–1.2 | **PLACE** | `1st!` punches. | centre — the hero | **nothing** |
| 1.2–2.6 | **REWARD** | `+100` punches; the bar runs underneath it. | drops one lane to the reward line | **nothing** |
| 2.6–5.0 | **REST** | Everything static and readable. Commentary (award / rivalry payoff) may fade into its one lane. CTAs obvious. | free — field, then CTAs | at most the one commentary lane |

Two eye-moves total (hero → reward → rest). The player can leave at any point from 0.0.

### 7.2 FTU (first banked results in a chair) — **7.5 s**, the SAME three beats

| t | Beat | Difference from steady state |
|---|---|---|
| 0.0–0.3 | ARRIVE | identical |
| 0.3–1.2 | PLACE | identical — **the hero does NOT yield** (§4.2) |
| 1.2–4.9 | REWARD | identical beat, held **3.7 s** instead of 1.4 s, and the reward line carries its clause: *"They raise your season tier."* The extra 2.3 s is the clause's read floor at the surface's own ~0.3 s/word rate — nothing new appears, one line grew. |
| 4.9–7.5 | REST | identical |

**7.5 s, not 16 s.** The delta between a first race and a hundredth is one sentence and 2.3 seconds. If
the director still finds 7.5 s long, the knob to turn is the REST tail, not the teaching.

### 7.3 Sponsor role

Identical skeleton, both passes. HERO = the show-result headline; SUPPORT 1 = the final field; SUPPORT 2
= the same Rally-Points line. Two chairs, one screen, one dramaturgy. Do not build a sponsor-flavoured
second copy of the clause (this confirms the shipped Q3 ruling).

### 7.4 The countdown

Suppress the visible `Next race in: N` for the duration of the REWARD beat, and only then. Carried rider
from `M6_ECONOMY_REVIEW` S5 / spec Q4, still unbuilt, and it matters more now that there is exactly one
thing on this screen worth reading. The phase's real advance authority is untouched — this is a
visibility rule only.

---

## 8. Copy

Registers, exact strings, all inside the existing `TailCopy` discipline (no literals in presenters, all
localized, no glossary proper noun, `BANNED_WORDS`-clean, ~1.4× German-class safe):

| Key | String | Notes |
|---|---|---|
| `resultsRallyLabel` | `Rally Points` | existing |
| clause | `They raise your season tier.` | **Shortened from the ratified pair.** "You never spend them" is the COUNT-vs-FILL contrast — but a contrast needs both terms on screen, and Coins are no longer narrated here (§1.3). Drop it; it moves to the Paddock where Coins are taught. Shorter copy is also the cheapest localization headroom on the page. |
| `econPrimerCoins` / `econPrimerCoinsShort` | — | **Retired from this surface.** The string may live on until the Paddock claims it; it must not render on the finish screen (§1.2). |

**Standing constraints re-affirmed:** "Race Now", "Sponsor a Race", never "spectator"/"bot"; proper
nouns never auto-translate; rows and racers carry no rings, strokes, marker bars or slash marks; every
line survives ~1.4× expansion by wrapping, never by clipping and never by a box sized to the English.

---

## 9. What I am NOT deciding — flagged as separate work

1. **The Coin sink** (a reachable garage with 3–4 cosmetics at 150–300). Economy designer + UI designer
   + a mission. **This is the highest-value item on this page.** §6.1.
2. **The RP segment size** (my recommendation: 500). Economy designer. §6.2.
3. **The season thresholds** (6,000 / 15,000 / 30,000). Mission 9 gate territory, per the existing spec.
   §6.2 makes the bar readable without touching them; it does not make them right.
4. **A first-sponsor-round RP floor.** Economy designer. §6.5.
5. **The first-win sticker's art and its home** (an authored decal on a visible face; the Paddock as the
   place to see it again). Art pipeline + a mission. §3.2.
6. **Clearing the race HUD at the finish** and de-duplicating the standings strip (E3/E4). Almost
   certainly a UI-engineering fix, not a design one, but it is a third of the clutter the director is
   reading and it must not be lost.
7. **The landscape roll-call clip and the surface bleeding behind `Sponsor a Race`** (E7/E8). Bugs; route
   to the UI engineer.
8. **`deliverRoundStory` on the legacy machine** (§B16) — still needs a director call, unchanged by
   anything here.

No new backend system is proposed anywhere in this document. §4.3, §5.2 and §6.2 are all derivations
over data the client already holds.

---

## 10. Acceptance — how we know this worked

Structural (a suite can hold these):

1. At most **three content elements** are painted at any instant, and at most **three numbers**.
2. **Exactly one element is animating at any sampled instant**, from t = 0 to the end of the tail,
   sampled at ≤ 0.25 s. This is the invariant that encodes "motion is the narrator."
3. **No region appears, disappears, resizes or moves after t = 0**, on every device row in the matrix,
   in every locale, primed and unprimed. Mutation-test it by re-introducing the rotation and proving it
   bites.
4. Placement, the RP delta, the bar and the field are **present continuously** for the screen's whole
   life on every composition, including the narrowest. Commentary is the only content that changes.
5. The clause renders **iff** `seasonRP < segment`, derived — with no persisted flag anywhere in the
   path.
6. Steady-state tail ≤ **5.0 s**; FTU tail ≤ **7.5 s**; CTAs hit-testable at t = 0 in both.
7. A win moves the bar **≥ 15 %** and a last-place finish **≥ 4 %**, asserted against
   `RallyPoints.placementTable()` and the segment constant, never against literals.
8. No string on this surface promises a spend path (grep the rendered copy for a Coin-purchase claim
   while `Ledger.spend` has no production caller). **Make this a test** — it is the guard against §1.2
   coming back.

Human gates (`FEEL` / `WATCH`, not self-certifiable — these are the ones that matter):

9. Hand the phone to someone who has never played. After their first race: **"what just happened?"**
   They should say their place first, unprompted. If they say anything else, the hero is wrong.
10. Same person, after ~5 races: **"what are Rally Points for?"** — answerable without being told.
11. **Do NOT ask them "what are Coins for?"** until there is a sink. If they ask *us* unprompted, that is
    the strongest possible evidence for §9.1 and should be logged as such.
12. Portrait phone, held at arm's length: is `+100` readable **without leaning in**? That is the
    director's original complaint and it is the only test of §6.3 that counts.
13. Does the 7.5 s FTU pass feel like a reward or like a wait? If it is a wait, cut the REST tail, not
    the clause.

---
---

# ADDENDUM — 2026-08-01, second dispatch

**Trigger:** director directive — *"Make sure our design for the finish screen both on FTU and regular
timing thinks about the emotions we want the user to feel. Excitement and reward for victory. The
desire for vengeance if they lost."*

`[DESIGN]: CONCERNS` — §1–§10 above are a correct **information** model and a **flat** emotional one.
Everything above stands unamended. What follows adds the outcome layer it is missing. §17 REPLACES
§7.1 and §7.2.

---

## 11. The emotional design — two passes, named

### Ruling 11.1 — There are exactly **two passes**: **THE FLAG** and **THE CHASE**.

*Rationale: two is the smallest number that can carry "I won" and "I want another go", and every extra
pass is a third register nobody has time to learn in five seconds.*

| Pass | Fires when | The emotion, in the game's own vocabulary | The sentence the player should leave with |
|---|---|---|---|
| **THE FLAG** | racer, `placement == 1` | Triumph, ownership — *"that one was mine."* | "I did that." |
| **THE CHASE** | racer, `placement > 1` | **A rival to settle** (GameDesign §5, day layer) + **"one more race"** (session layer) — unfinished business, never consolation | "I'll have them next time." |

The names matter for the build: they are what the code branch, the beat sheet, and the test all say,
so nobody has to ask whether "loss" means 2nd or 8th.

### Ruling 11.2 — There is **no MIDFIELD pass. Midfield IS the Chase**, and the Chase is the DEFAULT screen.

*Rationale: a distinct midfield register would have to say something like "not bad", and "not bad" is
consolation — the exact tone that turns a loss into a pat on the head.*

Be honest about the arithmetic: on an 8-kart grid, **7 of 8 outcomes are the Chase**, and once the
field contains real players a given human wins far less than 1-in-8. **The Chase is the screen this
player will see hundreds of times; the Flag is the exception.** So the build order inverts the
intuition:

> **Design and build the Chase first. The Flag is the Chase plus ceremony.**

A screen tuned only for 1st is a screen tuned for the rare case, and it is exactly how a finish screen
ends up reporting instead of feeling.

### Ruling 11.3 — **PODIUM is not a register. It is already in the ledger.**

*Rationale: 2nd and 3rd are expressed by the three facts that are already on screen — the place numeral,
the row you sit in, and a placement-dominant RP delta (`{100, 80, 65, 52, 42, 34, 28, 24}`) — and a
fourth statement of the same thing is noise.*

A podium finish gets the Chase, whose antagonist for 2nd place is **the winner** by construction (§13.1).
That is the correct and free result: the only finish where naming the winner is fair is the one where
you nearly were the winner.

### Ruling 11.4 — **NEAR MISS is a modifier on the Chase, not a third pass.** §13.5.

*Rationale: it changes one box's content and one crossfade's motion class — that is a modifier; a pass is
a different score.*

---

## 12. What changes between the passes, and what must never

A47 is binding: **the region inventory, every box, and every position are identical on both passes.**
The outcome may reach exactly **five channels**, all of them paint, copy, timing or sound.

### Ruling 12.1 — The five channels, and nothing else.

*Rationale: naming the permitted channels exhaustively is what makes "the outcome must not move a box"
enforceable instead of aspirational.*

| # | Channel | THE FLAG | THE CHASE |
|---|---|---|---|
| **C1** | **Hero motion class** | **`reward`** (ζ 0.7 / 0.18 s) — the surface's one under-damped class | **`object`** (ζ 1.0 / 0.28 s) — arrives, does not bounce |
| **C2** | **Hero plate fill** | the **champion fill** (one paint on the existing `SlamPlate`) | the resting plate, unchanged |
| **C3** | **Commentary box CONTENT** | payoff / award / streak / `resultsWinPlain` | **the chase line** (§13) |
| **C4** | **Dwell distribution inside the fixed 5.0 s** | PLACE holds **1.2 s** | PLACE holds **0.7 s**; the 0.5 s goes to the still-beat and the chase tail |
| **C5** | **Sound + haptic name** | `ui.results.place.win` · `haptic("double", true)` | `ui.results.place.chase` · `haptic("light")` |

**C1 is the single most load-bearing line in this addendum.** An overshoot is a cheer. A cheer on 8th
place is the game laughing at you. Critically damped is the same information delivered with respect,
and it costs nothing — both classes already ship in `motion/classes.luau`.

**C2 constraint for the UI designer:** the champion fill **may not be `coin` gold or `accent` orange** —
invariant 3 spends both on currency identity. Pick a third value; it is a UI-designer call, not mine.
If no third value can be found that reads as *win* without stealing a currency's meaning, drop C2 and
keep C1/C3/C4/C5 — the design survives the loss of the plate paint. It does not survive the loss of C1.

### Ruling 12.2 — What must be **byte-identical** between the two passes.

*Rationale: every one of these, changed by outcome, is a way of punishing the player for losing.*

1. **The seven regions, their boxes, their order, their sizes** (A46/A47). No outcome-dependent geometry.
2. **The hero's type size.** `8th!` renders at the same 44 cap as `1st!`, in the same box, on the same
   plate geometry. Shrinking, dimming, greying, or de-plating the loser's place is punishment by
   typography — see F3.
3. **The field.** Static, plain rows, full finishing order, **no rings, strokes, marker bars, slash
   marks, arrows, deltas, or annotations of any kind.** Ever. Both passes.
4. **The Rally-Points block.** Same box, same `rpDelta` role at 34, same `accent` hue, same punch, same
   bar behaviour. A `+24` does exactly what a `+100` does. See F10.
5. **The teaching clause.** Gated on `seasonRP_preRace < SEGMENT` and on nothing else — never on outcome.
6. **The CTAs.** Same labels, same places, hit-testable at t = 0, no pulse, no glow, no arrow.
7. **The total duration.** 5.0 s steady, 7.5 s FTU, **both passes**. See F2.

### Ruling 12.3 — **The Commentary region is scheduled for a racer at RESULTS on EVERY outcome.**

*Rationale: it removes the last outcome-dependent geometry difference — and a bare win with an empty
ceremony lane was going to look thin anyway.*

`commentaryScheduled` becomes `true` for any racer-chair results screen (its content is the chase line,
the payoff, the award, the bait, the tease, or the plain victory line — one of these always exists).
This is still a t = 0 latched fact, so A47 is untouched, and it makes "why does this screen look
different?" structurally impossible between a win and a loss.

---

## 13. The vengeance mechanic — **THE CHASE**

### Ruling 13.1 — **The antagonist is the kart that finished DIRECTLY AHEAD of you.** Always. On every Chase.

*Rationale: it is the smallest distance between where the player is and where they want to be, it is the
opponent they were actually looking at, and the client can name it today with zero new data.*

The evidence for "zero new data": `ResultsParts.standings` (`ResultsParts.luau:690`) already builds the
**full sorted finishing order with display names** from `opts.roster` — the SemanticModel roster cell,
whose `Row` carries `displayName` and `finishedPlace` (the rank latched at the crossing). The
antagonist is `standings[myPlace - 1].name`. It is the row **immediately above the player's own row in
the list the screen is already painting.**

I considered and reject the alternatives:

| Candidate | Ruling |
|---|---|
| **The winner** (`standings[1]`) | **Reject as the default.** Naming 1st to a player who came 8th is a taunt, not a target. It coincides with 13.1 exactly when it should — at 2nd place. |
| **The tracked bogey** (`RollCallBogeyId`) | **Not a second antagonist — a second SENTENCE, and only when it is the same kart.** §13.3. |
| **"The one who passed you last"** | **Reject — it does not exist.** There is no per-racer pass log on the client; the drama beat stream is the sponsor's round story, keyed by kart, not a "who passed me" ledger. Building one is new server work for a line that (a) says the same thing as 13.1 most of the time and (b) risks reading as blame ("you got passed"). Not worth it. Flagged and closed. |

### Ruling 13.2 — Timescale is why. The finish screen is the **session** surface, so it gets the **session** antagonist.

*Rationale: the kart directly ahead is a one-race fact that powers "one more race"; the bogey is a
multi-day thread that powers "a reason to come back today" — and A43 already gave the bogey the
pre-race window, which is a strictly better home for it (it points at a race about to happen).*

Saying the bogey's name at the finish AND again ten seconds later on the grid is nagging. One
antagonist, one line, one surface each.

### Ruling 13.3 — The **rivalry upgrade**: the bogey changes the SENTENCE, never the antagonist.

*Rationale: when the kart that just beat you is also the rival you have been losing to, the record is the
strongest sentence on the page — and it is free.*

The chase line upgrades to the rivalry framing **iff all three hold** (all t = 0 facts):

1. `latched(bogeyId)` is non-nil, **and**
2. the bogey resolves to the kart directly ahead (the same identity the roll-call resolution already
   performs — human `u<userId>` against `avatarUserId`, cast archetype against the silhouette display
   name), **and**
3. the player is **behind** on the thread after this race: `bogeyLosses + 1 > bogeyWins`.

Condition 3 exists because a "you lead 4–2" framing on a screen where you just lost is confusing, and
confusion is the one thing a five-second screen cannot afford.

**Two traps, both mandatory:**

- **`RollCallBogeyId/Wins/Losses` MUST be `latched()` at t = 0.** `SponsorRound.publishRollCall` runs at
  **INTERMISSION top**, which lands *inside the results tail* — this is the same edge that produced the
  A41 lineup-swap defect the director reported. Read live, the chase line would rename its antagonist
  mid-screen. Latched, it holds the finished round's rival for the screen's life. **Mutation-test it:
  flip the attribute mid-tail and prove the rendered line does not change.**
- **The record must count the race just run.** The attributes are the PRE-race record, so the client
  renders `losses + 1`. A record that omits the race the player just watched is a lie they can catch.

### Ruling 13.4 — The copy. Exact strings, `TailCopy`, all names as params.

*Rationale: this is a five-second screen for eight-year-olds in twelve languages; every word is budget.*

| Key | String | Fires when |
|---|---|---|
| `resultsChaseAhead` | `{rival} got you. Next one's yours.` | Chase, default |
| `resultsChaseClose` | `Photo finish! {rival} held on. Go again.` | Chase, near miss (§13.5) |
| `resultsChaseRival` | `{rival} leads you {l}–{w}. Settle it.` | Chase, rivalry upgrade (§13.3) |
| `resultsWinPlain` | `That one was yours.` | Flag, when no payoff/award/bait/tease is scheduled |

Every line is two short clauses: **who**, then **forward**. Nothing looks backward, nothing evaluates
the player, nothing states a mistake.

**Ruling 13.4a — NEW STANDING COPY RULE: no pronoun may refer to an injected proper noun.**
*Rationale: a translator never sees the name, so they cannot resolve its gender or number — "get them
back" is unlocalizable in every gendered language.* Every string above is pronoun-free with respect to
`{rival}`. Add this to the `TailCopy` discipline and grep for it.

**Localization headroom**, against the fixed 240 px commentary box at the surface's own metrics
(`GLYPH_EM` 0.62, 2-line cap): ~27 chars/line at 14 px, ~35 at the 11 px floor. English bodies here are
18–27 chars; with a 12-char cast name and ~1.4× German-class expansion the longest (`resultsChaseClose`)
lands at ~56 chars and derives to ~13 px across two lines. **It wraps; it never clips and the box is
never sized to the English.** `resultsChaseClose` is the only line with no headroom to spare — if a
locale forces the 11 px floor, cut `Photo finish! ` from that locale's string, never the forward clause.

**Voice check:** no `BANNED_WORDS` ("spectator", "bot", "ai", "npc", "tutorial", "practice mode",
"sabotage", "rigged"); proper nouns injected and `AutoLocalize = false`; "Race Again" / "Sponsor a Race"
untouched.

### Ruling 13.5 — The **near miss is real, and it is the loudest thing a losing screen ever gets** — in the commentary lane, never on the hero.

*Rationale: losing by a fraction is a completely different emotion from losing by a lap, and the screen
currently cannot tell them apart; but the loudness must land on the forward-pointing sentence, because
celebrating the place itself would be celebrating a loss.*

**Trigger — derived, never authored:** the finishing margin to the kart directly ahead is
`Gap(me) − Gap(ahead)`, both being the **frozen finish-tick gap-to-leader in studs**
(`FinishOrder.freezeGap` / `KartRaceScore:182`, already replicated on the `RaceState` row). Near miss
fires when that margin `<= SponsorTuning.closeFinishGap` (**85 studs ≈ 1 s at the locked 85 studs/s top
speed**). That constant is **the game's own existing definition of a photo finish** — it is what
`DramaScore.finish` already pays a sponsor for. Read it from `SponsorTuning`; never restate it.

**The three deltas, and only these three** (§17.4):
1. the line is `resultsChaseClose`;
2. it arrives **0.3 s earlier**, because it is the point of the screen;
3. its crossfade uses **`reward`** instead of `fast` — the one overshoot a losing screen ever gets, and
   it is on a word, not on a place.

**Ruling 13.5a — the copy never quotes the margin.** *Rationale: studs→seconds is an estimate, and a
wrong "by 0.4s" is worse than no number at all.* The threshold decides whether the sentence fires; the
sentence never states a value.

**Ruling 13.5b — never fake it.** *Rationale: a false "Photo finish!" on a twenty-second gap is a
visible lie, and §1.2 is this document's precedent on what a visible lie costs.* If the margin is
unavailable, **every Chase gets `resultsChaseAhead`** — do not substitute "2nd place ⇒ near miss".

**Scope:** the margin needs the per-kart frozen `Gap` surfaced onto the roster `Row` (it is replicated
already; the roster simply does not read it). That is **client plumbing, not server work** — §19. Ship
the Chase on the data that exists today and land the near-miss variant behind that one field; if it
slips, nothing breaks.

### Ruling 13.6 — How it points at `Race Again` without nagging. Three rules.

*Rationale: the CTAs are already the brightest interactive objects on the screen and already reachable at
t = 0 — anything added to them is decoration on a solved problem.*

1. **The line aims at the RACE, never at the control.** No "Tap", no "Press", no "Hit Race Again", no
   arrow, no `←`. "Next one's yours" / "Go again" / "Settle it" name the *next race*; the button is
   simply the nearest way to get one.
2. **It is the LAST word, not the first.** The chase line lands at the REST beat, after the ledger has
   been stated. The eye path is hero → reward → field → commentary → CTAs: a straight run down the
   ceremony lane and out into the CTA lane. Vengeance is what the player is holding when they leave.
3. **It never touches the CTAs' presence, position, enabled state, or paint.** No pulse, no glow, no
   selection change, no gating. A CTA that pulses is a nag; a CTA that is already there is an offer.

---

## 14. Victory, made to feel like victory

### Ruling 14.1 — Six things 1st gets that 4th does not. All cheap, none new art.

*Rationale: ceremony has to be built from objects that already exist, or it never ships.*

| # | What | Cost |
|---|---|---|
| **V1** | **The overshoot.** Hero plays `reward` (ζ 0.7). Nobody else ever does. | zero — the class ships |
| **V2** | **The champion plate fill** on the existing `SlamPlate` — the one warm object on the screen. | one paint value (UI designer; not `coin`, not `accent`) |
| **V3** | **Dwell.** PLACE holds **1.2 s** vs the Chase's 0.7 s — the plate is the point, so the screen lets you look at it. Taken from REST, **not** from the total. | zero |
| **V4** | **A sound.** `ui.results.place.win` vs `ui.results.place.chase`, through the existing name-only `UiSound` seam (unregistered names degrade to silence). | two hook names now; assets = sound-designer work |
| **V5** | **A haptic.** `haptic("double", true)` on 1st; `haptic("light")` otherwise. This game lives in a hand. | zero — the seam ships |
| **V6** | **The commentary box leads with the payoff.** `resultsPayoffRival` ("You finally beat {rival}!") already exists and already replicates (`ResultsRivalPayoff`); on a win it takes the box ahead of award/bait/tease. | zero |

### Ruling 14.2 — What 1st does **not** get.

*Rationale: every one of these buys ceremony by taking honesty, time, or hierarchy away from something
that was already right.*

A bigger numeral (44 is everyone's cap — a place is a place); a longer screen (5.0 s both); a second
plate; a bigger RP number (§6.4 stands — do not inflate a win); a second currency; a layout change.

### Ruling 14.3 — Flagged as separate work, deliberately **not** proposed here.

*Rationale: the six above are the 90 % that ships this week; art is the 10 % that must not hold it
hostage.*

Confetti or a particle system; an authored winner's badge or trophy art; a bespoke victory jingle asset.
**None is required for the Flag to read as a win.** If the director wants one, it is an art/sound
mission, scheduled after the motion/copy/sound-hook work lands.

---

## 15. The FTU pass

### Ruling 15.1 — **The FTU pass is always THE FLAG**, because the FTUE authors the win (pillar 2, `FTUEWinGuarantee`).

*Rationale: stating it removes the temptation to build an FTU-specific celebration for an outcome that is
already covered.*

### Ruling 15.2 — A first-timer gets **the SAME ceremony as a veteran winner. Not more.**

*Rationale: ceremony proportional to achievement is what makes ceremony mean anything — and the FTUE win
is the least-earned win in the game.*

Three reasons, in order of weight:

1. **It would invert earned emotion.** If the authored win is the loudest celebration the player ever
   receives, then their first *real* win — the one they actually earned, three races later — is
   quieter. That teaches "the game was nicer to me before I was any good," and it devalues the currency
   of celebration for the rest of the player's life in the game.
2. **§4.1 already ruled one screen.** Two ceremonies is two screens by another route.
3. **The first-timer already gets more, and it is more of the right thing.** 7.5 s instead of 5.0 s, and
   one sentence nobody else sees. That is *comprehension*, not noise — and comprehension is what a
   first-timer is short of.

### Ruling 15.3 — The FTU delta is **dwell on the REWARD beat, and nothing else.**

*Rationale: it is the same claim §7.2 made, now stated as an outcome rule so it cannot drift.*

Identical hero treatment, identical plate, identical sound, identical haptic, identical commentary
schedule. **The one and only difference between an FTU win and a veteran win is 2.5 s of reading time
on the Rally-Points block** (§17.2).

### Ruling 15.4 — The Chase pass must still be correct under the FTUE, and must be tested there.

*Rationale: the win guarantee has a documented escape hatch — a player who does not drive, drives in
reverse, or makes no track progress — and that player must not hit an untested branch on their first
minute in the game.*

If the guarantee does not fire, the Chase runs **with the teaching clause**, exactly as written. This is
why the clause is gated on `seasonRP` alone and never on outcome (12.2 §5): a first-timer who somehow
lost still has to be taught what Rally Points are.

---

## 16. The sponsor chair

A sponsor has no place, so the two passes substitute one fact each and change nothing else. Their
victory is **THE SHOW** — the round had a story — and it fires when the round-story headline exists
*and* the settled drama cleared the first Showstopper threshold (`SponsorTuning.showstopper.thresholds[1]`
= 50, the game's own "you charged the meter" line, already the anchor of the sponsor Coin curve). That
pass takes C1–C5 verbatim: `reward` on the story headline, the champion fill behind it, the 1.2 s dwell,
`ui.results.place.win`, and the commentary box carrying the award or `That was a show.` Their Chase is
**THE QUIET ROUND**, and their antagonist is not a racer — it is **boredom**, because pillar 5 says
sponsors direct drama rather than target people, so naming a kart as a sponsor's antagonist would be the
wrong lesson in the wrong voice. The line is `resultsSponsorQuiet` = `Quiet one. Make the next one
loud.` — no name, no blame, forward-pointing, and it points at `Sponsor Again` by exactly the §13.6
rules. Everything else — the same seven regions, the same Rally-Points block, the same recap band, the
same 5.0 s / 7.5 s totals — is unchanged, and §6.5's unresolved `+0` first-round problem is unchanged
and still flagged.

---

## 17. The revised beat sheets — **REPLACES §7.1 and §7.2**

Both principles still govern: **one moving thing at a time** (2.1b), and **the CTAs are reachable from
frame 1**. Totals are unchanged; the outcome redistributes time *inside* them. `A6.1`'s countdown
suppression fades ride inside the REWARD beat as before and are not restated per row.

### 17.1 THE FLAG — steady state, **5.0 s**

| t | Beat | What moves (exactly one) | What the eye is doing |
|---|---|---|---|
| 0.00–0.30 | **ARRIVE** | the surface as one group (`materialize`, `container`). Field final, coin chip settled, every box at final geometry, race HUD gone | settling |
| 0.30–1.50 | **PLACE** | `1st!` — champion plate fill, **`reward` overshoot**, `ui.results.place.win`, `haptic("double", true)` | pinned to the centre. This is the beat the whole screen exists for |
| 1.50–2.80 | **REWARD** | `+100` punches (`reward`), then the bar runs beneath it (`object`) — sequential, never together | drops one lane to the reward line |
| 2.80–5.00 | **REST** | at most the commentary crossfade: payoff → award → bait → tease, else `That one was yours.` | free: the field, then the CTAs |

Two eye-moves. PLACE = **1.2 s**. Exit available from 0.00.

### 17.2 THE FLAG — FTU, **7.5 s**, the same four beats

| t | Beat | Difference from 17.1 |
|---|---|---|
| 0.00–0.30 | ARRIVE | none |
| 0.30–1.50 | PLACE | **none.** Same overshoot, same plate, same sound, same haptic (§15.2) |
| 1.50–5.20 | REWARD | identical motion, finishing at 2.80 exactly as in 17.1; held **3.7 s**. The clause is painted from t = 0 (geometry is fixed), so **nothing new appears at all** — the extra 2.4 s is pure read time |
| 5.20–7.50 | REST | none |

**The entire difference between a first race and a hundredth is one sentence and 2.5 seconds of
silence.** If the director finds 7.5 s long, cut REST, not the clause (§10.13).

### 17.3 THE CHASE — steady state, **5.0 s**

| t | Beat | What moves (exactly one) | What the eye is doing |
|---|---|---|---|
| 0.00–0.30 | **ARRIVE** | identical to 17.1 | settling |
| 0.30–1.00 | **PLACE** | `5th!` — resting plate, **`object`, critically damped**, `ui.results.place.chase`, `haptic("light")` | centre, briefly. The fact is stated plainly and the screen moves on |
| 1.00–2.30 | **REWARD** | `+42` punches (`reward`), then the bar runs (`object`) — **identical in every respect to a win's** | drops one lane |
| 2.30–2.70 | **THE STILL** | **nothing. Deliberately.** The only 0.4 s on either pass where no element has velocity | **finds the field — and the row directly above its own.** This beat exists for exactly that |
| 2.70–5.00 | **CHASE** | the chase line fades into the commentary box, naming the kart in the row the eye just found | commentary → CTAs |

PLACE = **0.7 s** (0.5 s shorter than the Flag); that 0.5 s buys THE STILL and a longer chase tail.
Total **5.0 s — never one frame longer than the Flag.**

**Why THE STILL is the design, not a gap.** The chase line lands on a name the player has *already found
for themselves* one second earlier. That is the difference between the game telling you who to beat and
you deciding it — and it is free, because it is made of nothing.

### 17.4 THE CHASE — near miss, **5.0 s**

Identical to 17.3 with the three deltas of §13.5 and no others: THE STILL runs 2.30–2.40 (0.1 s — the
player already knows who it was), the chase line is `resultsChaseClose`, and its crossfade uses `reward`.
**The hero is untouched** — no plate, no overshoot, no extra dwell. The loudness is on the sentence.

### 17.5 The sponsor chair

17.1 / 17.2 / 17.3 verbatim, with the hero = the round-story headline and the antagonist = the quiet
round (§16). Two chairs, one dramaturgy, two passes. Do not build a sponsor-flavoured second copy of
anything.

### 17.6 Reduced motion

Both passes place every spring at its terminus on the frame it is armed, exactly as A6.3 specifies.
**The outcome distinction survives reduced motion in three of five channels** — plate fill, copy, sound,
haptic — and is lost only in C1/C4, which is correct: a player who asked for less motion asked for
exactly that. No branch is needed; every animated value here is decorative.

### 17.7 Skip

Skip lands the same settled state on both passes: hero at rest, delta at full opacity, bar at `fillTo`,
countdown restored, **the commentary box already on its chase / victory line**, nothing airborne. A
player who skips a loss still leaves holding the name.

---

## 18. What we must NOT do

Named so a reviewer can point at one. Every entry is a way this design fails in practice.

| # | Failure mode | Why it is fatal |
|---|---|---|
| **F1** | A **"you lost" plate** — `Defeated`, `Better luck next time`, `Nice try`, `So close!` as a headline, a sad face, a downward chevron | The place numeral IS the result. Stating it a second time in words is the definition of rubbing it in |
| **F2** | Making the **losing screen longer** than the winning one | Time on a screen is how a game says "this mattered". A longer loss is a punishment measured in seconds. **Testable: `defeatTotal <= victoryTotal`, always** |
| **F3** | **Shrinking, dimming, greying or de-plating the loser's hero** | Punishment by typography. `8th!` is the same node at the same size on the same plate |
| **F4** | **Blaming the player.** "You were passed on the last lap", "you spun out", a mistake tally, a lap-time comparison, a "best lap you didn't beat" | The antagonist is a kart, never the player. A five-second screen has no way to make criticism land kindly |
| **F5** | **Naming the winner to a back-marker** | A target you were never near is a taunt. The antagonist is the row directly above yours — for 8th that is 7th |
| **F6** | **Annotating the field rows** — ▲/▼, `+2`, a marker on the winner's row, a highlight on the antagonist's row, rings, strokes, marker bars, slash marks | Standing rule, both passes, forever. The chase line is a **sentence in the commentary box**; the field stays plain |
| **F7** | **Nagging the CTA** — pulse, glow, arrow, auto-focus change, "← tap here", or gating it behind the ceremony | It is already reachable at t = 0 and already the brightest interactive object. Anything added is decoration on a solved problem |
| **F8** | **Rigging the next race off the loss** — quietly nerfing the rival you were told to beat | `RivalryRecord` is a story surface only (§6.5); the FTUE stays the only authored outcome in the game. "Get them next time" becomes a lie the moment the game arranges it |
| **F9** | Letting the **outcome change geometry** | A47. The chase line lives in an already-scheduled box (12.3); `placement` is a t = 0 fact, so the whole outcome branch is latched by construction |
| **F10** | Making the **reward beat apologise** — a smaller punch, a dimmer hue, a shorter fill, or a skipped beat for a small delta | A small number doing the same dance reads as honest. A small number doing a smaller dance reads as consolation, and consolation is the tone that kills vengeance |
| **F11** | Paying a win **more** to make it feel bigger | §6.4 stands. The win should feel bigger because it is *celebrated* more, not because it is *worth* more |
| **F12** | Holding the whole design hostage to **confetti** | C1/C3/C4/C5 are free and carry the emotion. Art is an upgrade, not a dependency |
| **F13** | A **third pass** | 11.2. Every register added is one more thing a seven-year-old has to decode in five seconds |

---

## 19. Data availability — what is derivable today, and what is new work

### Ruling 19.1 — **No new server system, and no new server field, is required by anything above.**

Available at RESULTS t = 0, client-side, already replicated:

| Fact | Source | Note |
|---|---|---|
| `placement` — the outcome switch | `ResultsPlacement` player attribute | already the hero's input |
| **the kart directly ahead, by name** | `ResultsParts.standings(M, opts.roster, localUserId)` → `standings[place-1].name` | the list the screen already paints |
| the winner's name | `standings[1].name` | same call |
| `rivalPayoffName` | `ResultsRivalPayoff` | the Flag's commentary |
| `bogeyId` / `bogeyWins` / `bogeyLosses` | `RollCallBogeyId/Wins/Losses` | **must be `latched()`** — §13.3 |
| the photo-finish threshold | `SponsorTuning.closeFinishGap` = 85 studs | derived, never restated |
| the RP segment | `SeasonRollover.SEGMENT_RP` | already built |
| sponsor drama + round story | the drama beat stream + `roundStory` | §16 |

### Ruling 19.2 — Exactly **one** piece of new plumbing, and it is client-side.

*Rationale: naming it precisely is what keeps it from becoming "we need a server change".*

Surface the per-kart **frozen finish `Gap`** (`RaceState.GAP`, written by `KartRaceScore:175-186`,
frozen by `FinishOrder.freezeGap`, **already replicated**) onto the SemanticModel roster `Row`, latched
at results t = 0. It gates the near-miss variant and nothing else. **If it slips, every Chase gets the
default line and the design still works** (13.5b).

### Ruling 19.3 — Flagged as separate work, not decided here.

1. **The champion plate fill value** — UI designer, constrained to neither currency hue (12.1 C2).
2. **Sound assets** for `ui.results.place.win` / `ui.results.place.chase` — sound designer. The **hook
   names ship now** and degrade to silence (`UiSound.play` never errors on an unknown name).
3. **Confetti / winner's art / a victory jingle** — art + sound missions, explicitly not required (14.3).
4. Everything already flagged in §9 is unchanged.

---

## 20. Acceptance — additions to §10

Structural (a suite holds these; each is a real defect if it fails):

14. **`defeatTotal <= victoryTotal`** on every profile, every device row, both chairs. The one test that
    encodes F2.
15. **The resolution dump is byte-identical between a 1st-place and an 8th-place screen** at every 0.25 s
    sample — same regions, same forms, same rects, same type sizes. Only paint, motion class, text and
    sound name may differ. Mutation: make one region outcome-conditional and prove it bites.
16. **The chase line names `standings[place-1].name` exactly** — and equals `standings[1].name` **iff**
    `place == 2`. Assert against the sorted list, never a literal.
17. **The chase line never renders when `placement == 1`, and never in the sponsor chair.**
18. **The commentary region is scheduled for a racer at RESULTS on every outcome** (12.3).
19. **The near-miss variant renders iff the margin `<= SponsorTuning.closeFinishGap`**, asserted against
    the constant. **No copy on this surface states a margin value** (13.5a).
20. **The bogey facts are latched**: flip `RollCallBogeyId` mid-tail and prove the rendered line does not
    change. This is the A41 defect class and it must be pinned.
21. **The rivalry line renders `losses + 1`** — the record counts the race just run.
22. **Only `placement == 1` arms the `reward` motion class on the hero.** Sample the class name; every
    other placement is `object`.
23. **The hero's type size, plate box and region rect are identical for `1st!` and `8th!`** (F3).
24. **No rendered string on this surface contains a pronoun bound to a name param** (13.4a) — grep the
    copy table. **`BANNED_WORDS`-clean, ~1.4× fixture wraps to ≤ 2 lines and never clips.**
25. **The clause renders iff `seasonRP_preRace < SEGMENT`, independent of outcome** — assert it on a
    losing FTU screen too (15.4).

Human gates (`FEEL` / `WATCH`, not self-certifiable — these are the ones that decide it):

26. **After a loss, ask "what are you going to do now?"** They should name the rival or say "go again",
    unprompted. If they say "I don't know", the Chase is not working.
27. **After a loss, ask "did the game make you feel bad?"** A "no" is required. Anything else is F1–F5
    leaking, and the specific word they use will name which one.
28. **Show a win and a loss back to back.** Ask which felt bigger. If they cannot tell, C1 and C2 are not
    doing their job — and C1 is the one to fix first.
29. **Watch the eyes during THE STILL (2.30–2.70).** Do they go to the field? If they do not, the beat is
    in the wrong place or the field is too far from the hero — move the beat, not the boxes.
30. **On the near-miss screen: does it feel like a story or like a consolation prize?** If consolation,
    the loudness is in the wrong channel — it has leaked onto the hero.
