# Tuned-values audit — the parallel Sponsor presenter vs everything we tuned

**Date:** 2026-07-31 · **Stage:** `parallel-sponsor` (roadmap Step 6)
**Commission (director, DECISIONS 2026-07-31, verbatim):** *"check the lessons and memory from
building sponsor view and for all the things we spent a lot of time tuning, make sure we're doing as
well or better."*

**Method.** Every tuned value or director-locked behaviour was extracted from the six named sources
with a `file:line`, then verified **against the presenter's code**, never against a round report. A
row is `MATCHED` only if the presenter expresses the same number or the same rule; `BETTER` needs a
stated why; `GAP` names what is missing; `N-A` names why the value cannot apply.

**Sources swept.** `docs/FEEL.md` · `docs/DECISIONS.md` (1137 lines) · `docs/lessons/*.md` (26 files)
· `docs/missions/M11_GATE_PACKET.md`, `M12_GATE_PACKET.md`, `M12_UI_FIX_SPEC.md`,
`M12_DESIGN_BRIEF.md` · `docs/ui/UI_SPEC_sponsor_motion.md`, `UI_SPEC_chaos_row_states.md`,
`UI_SPEC_racerlist_autoscroll.md`, `UI_SPEC_avatar_badges.md` · `UI_SPEC_sponsor_luauui.md` §11
D-1…D-15.

**Outcome.** **108 rows audited** (T1–T96 values + L1–L12 lessons):
**80 MATCHED · 20 BETTER · 3 GAP-FIXED · 4 GAP-QUEUED · 1 N-A**.
Counted by section — 1.1: 19 M / 5 B / 1 G✔ / 2 G? · 1.2: 14 M / 3 B / 1 N-A · 1.3: 9 M / 1 B /
2 G✔ / 1 G? · 1.4: 8 M / 2 B / 1 G? · 1.5: 11 M / 3 B · 1.6: 10 M / 3 B · 1.7: 9 M / 3 B.
A fifth item (TUNE-Q5) is queued as governance rather than as a value row.
Suites at close: game **2819** / LuauUI **2755**, both green; `stylua --check` clean on both trees;
11/11 legacy checksums unchanged.

**The headline.** The port holds its tuned values far better than a parallel rebuild has any right
to, and the reason is structural rather than diligent: most of the numbers that took sittings to land
live in **shared pure models** (`CommitBeatModel`, `ResultsSpotlightModel`, `ResultsLayoutModel`,
`SponsorTuning`, `SponsorTickerModel`, `SponsorStatusModel`, `CelebrationModel`, `SponsorHudModel`),
and both presenters consume the same ones. Where the port re-expressed a number itself, it did so in
two declared vocabularies (`TableMetrics`, `StoryTokens`) with the legacy line cited beside each
entry. **Every one of the five real gaps is in the thin band where the port re-derived a value
instead of citing one** — which is exactly the class this audit existed to find.

---

## 1. The table

Legend: **M** matched · **B** better · **G✔** gap, fixed this round · **G?** gap, queued ·
**N/A** not applicable.

### 1.1 Motion vocabulary and the beat table (`UI_SPEC_sponsor_motion`, spec §7)

| # | Item | Tuned value + source | Where the presenter expresses it | Status |
|---|---|---|---|---|
| T1 | The four spring tokens | `panel` 1.0/0.35 · `card` 1.0/0.28 · `pop` 0.7/0.18 · `fade` 1.0/0.5 (`UI_SPEC_sponsor_motion.md:78-81`; `DECISIONS.md:867`) | `LuauUI/src/motion/classes.luau:48-51` — `container`/`object`/`reward`/`decay`, the same four pairs; spec §7 maps them 1:1 and the game registers no parallel set | **M** |
| T2 | Solver form | omega = 2π/response, k = omega², c = 2ζomega, semi-implicit Euler (`:60-61`) | `LuauUI/src/motion/spring.luau:79-95` | **M** |
| T3 | Zero per-call magic numbers | a raw `{dampingRatio, response}` literal at a call site is refused (`:78` intent) | framework-enforced (`motion/classes.luau:139-171`), so the rule is mechanical rather than reviewed | **B** — legacy enforced it by convention |
| T4 | M1 pose materialize | `enter = "materialize"`, `container` | `HudScreen.luau:131` `POSE_TRANSITION`, used at `:389`/`:395` | **M** |
| T5 | M2/M4 pickup + fly-home, velocity handoff | `card` class; release velocity seeds the flight; a new grab ABSORBS the return (`:153-166`) | framework drag registry + `HandDock.luau:501`'s `grabAnchor`; `CardState.luau:95-100` states the absorb rule explicitly | **M** |
| T6 | M5 tap-to-arm staging spot | ONE fixed spot, deliberately not riding the aimed row (`§11 D-10`/`D-2`; `DECISIONS.md:948`), re-anchored above the SOURCE SLOT by review round 2 N13 | `init.luau:120-123` `STAGING_GAP_PX = 8` + `:1590-1617` — the source slot's **live** rect, re-read per frame | **B** — legacy centres over the dock, which put two of a three-card hand over a neighbour |
| T7 | Ghost centre-under-finger, no lift | `dragGhostLiftPx = 64` is DEAD; ratified feel is centre-under-finger (`§11 D-10`, gate round 11) | `HandDock.luau:501` `grabAnchor = "center"`, no lift anywhere in the namespace | **M** |
| T8 | Press→drag promotion | 14 px touch / 6 px mouse (`m5-xplatform-ui-input.md:53-56`; `SponsorGesture:97-98`) | `LuauUI/src/input/interaction_tokens.luau:29-32` — the same two numbers as framework defaults, with the ratified ranges published beside them | **B** — one rule on every acquisition path incl. `UIDragDetector` |
| T9 | M6 commit flight chases a LIVE target | re-read every frame; arrival on the perceptual radius, not the settle epsilon (`:226-231`; `DECISIONS.md:946` ARRIVE_PX) | `onCommitProxy = "flyToTarget"` (spec §7 M6); `PlayFlow.luau:37` names the causal frame | **M** |
| T10 | M6 flight carries the card icon ONLY | no avatar badge on the flight (`§11 D-1`; `DECISIONS.md:1033`) | `PlayFlow.luau:291` — the badge-bearing pill is held off the row until the land | **M** |
| T11 | M8 row wash | hit SETS to full instantly, `decay` carries it down; a re-hit RE-SETS (`:260-263`); GENERAL rows take the half wash | `RowBeats.luau:68-75`; `RacerList.luau:545-552` (`washScale`, legacy's `ROW_BG:Lerp` composite verbatim) | **M** |
| T12 | **M9 in-flight tell — the swell** | thickness **2 → 4** px, lit ink **0.35 → 0.0** across the wind-up, painted on the row stroke AND the map ring from one call (`CommitBeatModel.luau:42-45`, `:97-105`; `SponsorRacerList:528-548`, `:340-357`) | **WAS:** the map dot had 2→4 (inline), the row had `1 + 2*value` at transparency 0 — louder at commit, thinner at land, and the two channels disagreed. **NOW:** `TableMetrics.TELL` + `TableMetrics.tellStroke` (one home) consumed by `RacerList.luau:585` and `MapCanvas.luau:158` | **G✔** |
| T13 | **M9 in-flight tell — the rising RATE** | blink 1.15 Hz → 2.4 Hz, ramp power 1.6, dim floor 0.72 (`CommitBeatModel.luau:35-46`, `:72-90`) | not ported on either surface | **G?** — TUNE-Q1 |
| T14 | M9 reduced motion | a single quiet STATIC outline at the tell weight, no ramp, no blink (spec §7 M9) | `StoryFlow.luau:554-560` — the `decorative` timer places at the end value under RM, so the outline is static and at the land weight | **M** (legacy's own RM constants are 3 px / 0.3; the port lands 4 px / 0.0 — the same information, one rung brighter) |
| T15 | M10 gate-slot form entry pop | `reward` targeting rest; a form change re-targets FROM THE CURRENT SCALE; `play ⇄ cooldown` never re-pops (spec §7 M10; `UI_SPEC_chaos_row_states.md:81` 0.2 s Back-out) | not built — no gate-slot path in `init.luau`'s `storyPaths`, no firing | **G?** — TUNE-Q3 |
| T16 | M11 impact ping | self-retiring keyed region, expand + fade, never interrupted; 12 → 48 px over 0.5 s | `BeatLayer.luau:29`; `StoryTokens.luau:140-141`, `:152` | **M** |
| T17 | M12 cascade arc | comet between two LIVE dot positions, 12 → 20 px over 0.7 s | `BeatLayer.luau:29-30`; `StoryTokens.luau:142-143`, `:153` | **M** |
| T18 | M13 crowd surge | needle re-target with overshoot, `reward`; 0.18 out + 0.32 back | `StoryTokens.luau:161` `surgeS = 0.5` with the legacy split cited | **M** |
| T19 | M14 Showstopper bank | `Motion.pop` UIScale 0.9 → 1.0, earned overshoot — THE named reward beat (`DECISIONS.md:867`) | `HandDock.luau:559-565` `transition = { enter = "materialize", class = "reward" }` | **M** |
| T20 | M15 confetti | fleck 8×10, fly 1.0 s, stagger 40 ms, ±150° tumble, RM hold 0.8 s (`DECISIONS.md:1031`) | `StoryTokens.luau:129` `confettiFleck = 8`; `:154-157` all four timings, each with its legacy line | **M** |
| T21 | M16 finish flag pop | `reward`, once per latch, RM = instant Visible | `StoryFlow.luau:730-763` — presentation-transform scale spring on the row's flag path, RM branch at `:735` | **M** |
| T22 | M17 toast in/out | supersede at the read floor; a showing toast's floor is never truncated by priority | framework toast scheduler via `Toasts.build`'s `key`/`priority`/`readFloor` (`Toasts.luau:126-133`) | **B** — see T40 |
| T23 | M22 autoscroll ramp | model-owned dwell → penetration speed → start ramp → exit decay | `LuauUI/src/input/autoscroll.luau` — see §1.3 | **M** |
| T24 | M23 results reveal | materialize in, **instant** out — the one declared asymmetry | `ResultsScreen.luau:247` | **M** |
| T25 | M25 omen billboard | spawn `reward`; ring is a TIMER, never a spring; final flourish a discrete band under RM | `OmenState.luau:270`, `:444`, `:457-479`; `OmenBillboard.luau:38-41`, `:151-164` | **M** |
| T26 | M26 FTUE pull line | both endpoints re-read every frame; **dies permanently on the first touch of the card** | `FtueLayer.luau:15-21`; `StoryFlow.luau:1384-1387` `killPullLine`, `:1250-1251` guard | **M** |
| T27 | Rest costs zero | a settled motion detaches; a frame with nothing live opens no transaction | pinned live: `luauui_sponsor_story.spec` — 30 frames, zero signal/memo/observer/clock-write growth | **B** — legacy has no such assertion |

### 1.2 Row states, the gate strip and the ring (`UI_SPEC_chaos_row_states`, `M12_UI_FIX_SPEC` Item 5)

| # | Item | Tuned value + source | Where the presenter expresses it | Status |
|---|---|---|---|---|
| T28 | Family hues | help gold (255,205,90) / hinder violet (150,120,220), LOCKED (`DECISIONS.md:965`; `:20`) | `TableMetrics.luau:276-277` — legacy's own constants through the sanctioned `direct` tint escape, after the director overruled the palette-role mapping (DV-1) | **M** |
| T29 | Recede ladder | highlighted 0.02 · ACTIVE 0.1 · idle RELATIVE 0.35 · GENERAL **and held-blocked 0.55** (`§11 D-4`; `M12_UI_FIX_SPEC.md:373-385`) | `TableMetrics.PLATE_ALPHA` (`:383-388`) as the COMPOSITE each rung actually paints, keyed off `RowState.Presentation.plate` | **M** |
| T30 | Held-blocked swatch | lerped 70 % toward neutral (90,92,100); GENERAL takes the gentler dim 0.45 | `TableMetrics.luau:629-638` `SWATCH_LERP = { full 0, dim 0.45, desaturated 0.7 }` | **M** |
| T31 | Blocked slash | 45° corner-to-corner bar on the blocking family's slot, 3 px | `TableMetrics.SLASH_POINTS` (`:524-527`) + `slashThickness = 3` (`:198`) — one definition, spent by the gate pill and the blocked card slot | **M** |
| T32 | Identity stroke at rest | ACTIVE 0.7 / RELATIVE 0.8 / GENERAL 0.85 (`:48`) | `TableMetrics.ROW_STROKE_ALPHA` (`:431-440`) — **superseded on the row itself** by director visual rounds 3+4 (a resting hairline read as "colored rings around the rows"), so the resting stroke is invisible and identity lives in the swatch | **B** — a director ruling, recorded at `RacerList.luau:566-572` |
| T33 | Drop verdict | wash ONLY, no ring (device round 1 DB-7); composite = `ROW_BG:Lerp(verdict, 0.35)` at the highlighted rung | `TableMetrics.VERDICT_WASH = 0.35` (`:455`) + `verdictPlateColor`; `VERDICT_STROKE_PX` deliberately deleted | **M** |
| T34 | Held card's own ring is neutral | always, on every scheme (`DECISIONS.md:946`; invariant 5) | no verdict branch on the ghost anywhere in the namespace | **M** |
| T35 | Gate pill anatomy | 44×22 play / 22×22 LOCKED-∞ / 58 px authored slot · corner 0.28 · stroke 2 px family @0.4 · 4 px inset · glyph 16 · ring 16 | `TableMetrics.luau:186-198`; `RacerList.luau:223-227`, `:255-266`, `:340-400` | **M** |
| T36 | Author badge | 28 px, centred on the pill's LEFT cap, rim 2 px neutral (232,236,244) @0.35, NEVER family-tinted | `TableMetrics.luau:123`, `:287`; `RacerList.luau:412-440` | **M** |
| T37 | Badge with **no name** is hidden, not a "?" plate | `§11 D-8` (kills the "mystery square") | `Toasts.luau:11-13`, `:60-65` — the region is present or absent, never a placeholder | **M** |
| T38 | The **seventh** badge surface (activity ticker) | `§11 D-14` — same size as the toast tag | `Ticker.luau` entry badge; `StoryTokens.luau:132` | **M** |
| T39 | Gate-strip density valve | strip ≤134; two live plays 58+4+58 = 120; if a future card breaks the sum the **older** badge sheds first (`:118`) | the LuauUI strip is a **content-width** HStack (`RacerList.luau:657-665`), max 120 < 134, and the name column is the `fill` that yields — so the overflow the valve exists for cannot arise, and nothing ever truncates | **B / N-A** — the deterministic shed order is unreachable by construction. If the card vocabulary ever grows a third slot, re-open this row |
| T40 | Ring FORM | 12 ticks, lit from 12 o'clock clockwise, edge retreating counter-clockwise; tick 2.5×5 at radius 5 in a 16 px box; ONE form for gate pill, omen ring and world billboard (ruling (a), `§11 D-3` withdrawn) | `TickRing.luau` (one construction, three consumers) + `TableMetrics.RING_SEGMENTS/ringTick/ringTickPoints` (`:207-250`) | **B** — legacy draws the same ring from two files; the port cannot drift them |
| T41 | Ring DRIVE | remaining = (gateTick − nowTick)/TICK_HZ, total anchored at the pill's first appearance, re-anchor UP on extend, never backward, one tick held lit while live (`:84-85`) | `TableMetrics.ringLit` (`:213-220`) + `RowState.ringAnchor`, off the framework's informational timer (amendment A21 / DV3-3) | **M** |
| T42 | LOCKED-∞ | tick = −1 → 22×22 glyph-only chip, NO ring | `RacerList.luau:257-266` `gateSlotWidthInf` | **M** |
| T43 | Own-play pill content | avatar badge + ONE continuous ring; no card glyph, no lock (`:25`) | `RacerList.luau:382-384` — the glyph is absent on the authored forms | **M** |
| T44 | Finished row | GENERAL-INACTIVE permanently, flag glyph, tap explains itself with a toast and no watch snap (`:63`, `:152`) | `init.luau:1399-1408`; `RacerList.luau:667-678`; copy via `SponsorHudModel.toastPushFinished` | **M** |
| T45 | Never colour-only | every state differs in a non-colour channel | `RowState.channels` / `CardState.channels` (`:189-192`) assert it as a matrix, in greyscale | **B** — a mechanical gate legacy has by review only |

### 1.3 Drag-edge autoscroll (`UI_SPEC_racerlist_autoscroll`)

| # | Item | Tuned value + source | Where the presenter expresses it | Status |
|---|---|---|---|---|
| T46 | Band height | 40 px landscape / 44 px portrait (`:49`) | `autoscroll.luau:51` `BAND_H`; `TableMetrics.luau:128-129` per size class | **M** |
| T47 | Dwell | 300 ms, reset on leaving both bands or crossing; jitter inside does not reset (`:62-65`) | `autoscroll.luau:56`, `:196-225` | **M** |
| T48 | Speed model | `v(p) = 100 + 400p`, linear in penetration (`:77-79`) | `autoscroll.luau:59-60`, `:171-176` | **M** |
| T49 | Start ramp | 150 ms quad ease-out from the ARMING instant (`:82`) | `autoscroll.luau:58`, `:173` | **M** |
| T50 | Membership is the POINTER POINT | mandatory — band and drop hit-test share one coordinate (`:53-57`) | `autoscroll.luau:18-20`, `:132-158` | **M** |
| T51 | Per-frame hover re-resolve | `_previewAtRow` every scroll frame, immediately after the write (`:99-107`) | `virtual_list.luau:657-670` — `refreshTargets()` in the same frame as `scrollTo` | **M** |
| T52 | Canvas-end clamp | trim to zero, no bounce, **stay armed** (`:94-97`) | `autoscroll.luau:240-246` | **M** |
| T53 | Short list is INERT | `maxScroll <= 0` → never arm, no affordance (`:111`) | `autoscroll.luau:186-191` | **M** |
| T54 | Exit ease, leaving both bands | 80 ms ease-out to 0 (`:92`) | `autoscroll.luau:61`, coast channel | **M** |
| T55 | **Exit ease on a DIRECT band cross** | the same 80 ms, applied uniformly — "reversing direction mid-ease reads better than a hard velocity flip" (`§11 D-11`; `SponsorGesture:762-770`) | **WAS:** a cross went straight to `dwelling` with delta 0 — a hard cut from ~490 px/s. **NOW:** `beginCoast`/`coastVelocity` in `autoscroll.luau`, decaying under `dwelling` and `exiting` alike | **G✔** (ledger OWN-D59) |
| T56 | **Haptic on arm** | one UI-tick at the moment scroll starts, touch only, never per-frame (`:137-138`) | **WAS:** `justArmed` computed and discarded. **NOW:** `init.luau`'s frame loop → `StoryFlow:onAutoscrollArmed()` → `celebrate:autoscrollArmed`, mapped by the game | **G✔** (ledger OWN-D61) |
| T57 | **Chevron affordance** | ▲/▼ pinned to the active edge, NEUTRAL_RING (150,152,160), 24 px, hidden at the canvas end, 40 % armed, 100 % + 0.8 Hz pulse active, 120 ms fade (`:129-136`) | not built | **G?** — TUNE-Q2 |
| T58 | Gamepad | out of scope — no dwell/band path (`:147`; `§11 D-12`) | `autoscroll.luau:43-45` + `virtual_list.luau:643-653`: non-pointer sessions never autoscroll, because focus-follows-navigation scrolls the host | **B** — satisfied by a mechanism that does not assume engine selection |

### 1.4 Toasts, messages and copy

| # | Item | Tuned value + source | Where the presenter expresses it | Status |
|---|---|---|---|---|
| T59 | Toast **read floor 2.5 s** | `SponsorCelebration:139` "~2.5 s with a fade"; DV-6 raised it to a floor | `TableMetrics.luau:133-135` `toastDurationS`/`toastReadFloorS`, both 2.5; passed at `Toasts.luau:129-130` | **B** — legacy caps the queue but never FLOORS a read |
| T60 | One toast per attempt | `toastMaxQueued = 3` drops the oldest (`SponsorHudModel.luau:342`, `:569-574`) | `Toasts.luau:23-28` — `key = <block code>` gives the scheduler supersede-by-subject, so a mashed illegal drop REPLACES rather than stacking | **B** — a mechanism, not a convention |
| T61 | The land tag keys on its SUBJECT | two plays on one kart supersede; two karts do not | `Toasts.luau:42`, `:30-34` `landtag:<kart>` | **M** |
| T62 | Toast plate | 30 px bare / 36 px tagged · max 300 · corner 9 · pad 10/3 · gap 8 · type FIXED 16 · badge 28 | `TableMetrics.luau:171-180`, each with its `SponsorCelebration` line | **M** |
| T63 | Tone colours + priority | blocked pink / showready gold / two family hues; blocked outranks everything | `TableMetrics.luau:597-617` — legacy's own `TOAST_TONE_COLOR`, incl. the unmapped-tone fallback | **M** |
| T64 | Every block code has §15 copy; an unmapped code falls back to `legality` | `SponsorHudModel.luau:76-91`, `:580` | `Toasts.text` (`:47-50`) — byte-for-byte the same table, and the presenter spells no copy of its own | **M** |
| T65 | Message arbiter | host > celeb > toast, one at a time (`SponsorHudModel.luau:618-642`) | shared model consumed directly; `MessageLayer` renders the decision | **M** |
| T66 | Caption dwells | connect/read/streak 1.8 · dodge 1.2 · milestone 1.5 · cascade 2.2 · close 2.4 · stale 4.0 · defer re-try 0.25 | `StoryTokens.luau:163-169`, each with its legacy line | **M** |
| T67 | **Race-view toast ×1.4 scale** | screen-level overlay at y = 0.16, **1.4× UIScale** — the director's "bigger overlay text" (`DECISIONS.md:588`; `m5-xplatform-ui-input.md:131-135`) | the framework toast layer is always screen-level (the clipping cause is gone), but the pose-conditional ×1.4 is not expressed | **G?** — TUNE-Q4 |
| T68 | Omen teach-once, per FAMILY | help once, hinder once, session-scoped; then never again (`M12_UI_FIX_SPEC.md:795-805`) | `OmenState.luau:133-136`, `:416-433` | **M** |
| T69 | Proper nouns injected verbatim + the internal-name leak guard | `SponsorHudModel.formatCaption` / `isInternalKartName` | consumed directly; no copy is built in the presenter | **M** |

### 1.5 Results (`M12_UI_FIX_SPEC` Item 4 + addendum, S16 v2)

| # | Item | Tuned value + source | Where the presenter expresses it | Status |
|---|---|---|---|---|
| T70 | One piece at a time, authored order | economy → award → payoff, driven by the replicated tail clock (`M12_UI_FIX_SPEC.md:524-530`) | shared `ResultsSpotlightModel` consumed at `ResultsParts.luau:473-498` | **M** |
| T71 | Read floors | slam 1.2 · economy 2.5 · award 2.5 · story 3.5 · payoff 1.6 (`:524-530`) | `ResultsSpotlightModel.luau:76-79` — the same shared home both presenters read | **M** |
| T72 | Floors survive the phase boundary | a piece whose floor crosses RESULTS→INTERMISSION keeps showing (`:658-675`) | pinned by `luauui_sponsor_results.spec` (acceptance PS-R4) | **M** |
| T73 | Rested bands hold their reserved height | they do not reclaim — the CTA band must never jump under a thumb (`:553-559`) | `CelebrationSlot` fixed height (`ResultsParts.METRIC_DEFAULTS.celebrationSlot = 76`), plus the framework's `Region.reserved` as a live read (OWN-D48) so a lane that will never fill collapses instead of holding air | **B** |
| T74 | Skip = skip ALL, one meaning, no per-beat skip | (`:539-543`) | `ResultsScreen.luau:475-486` — ONE `skipEnabled` gate behind all three affordances | **M** |
| T75 | Skip latch is TAIL-scoped | reset only at a new round's results entry, not at every phase edge (`DECISIONS.md:1047`) | `ResultsScreen.luau:357-401` | **M** |
| T76 | Skip chip is never condensed | 44 px floor, mark **and** word (`:298-305`; review round 2 N7) | `ResultsScreen.luau:279-292`, `:2444-2462` — `minMax` width so the word always fits | **M** |
| T77 | **BOTTOM_BREATH = 12** | an aesthetic pad ON TOP of the physical safe floor, so the CTA stack never lands flush (`ResultsLayoutModel.luau:85`, `:166-169`; `DECISIONS.md:1047`) | `rootPolicy = "deviceSafeContent"` spends per-edge max(core, device), then `ResultsFlow` adds `padding = "m"` = **16 px** (`default_style.luau:62`). On a 34 px home band: port 34+16 = 50 vs legacy max(16,34)+12 = 46 | **B** — the breath is ≥ legacy on every edge, and it is a token rather than a constant |
| T78 | Band sizes | celebration slot 76 · hero 56 · CTA button 52×170 · tap floor 44 | `ResultsParts.luau:100-104`, read from `ResultsLayoutModel.tokens` rather than copied | **M** |
| T79 | CTA reflow point | two 170×52 side by side, 12 px gap; stack at `2·170+12 > safeWidth` (`:292-296`) | `ResultsScreen.luau:265-267`, `:1904-1926` — `ViewThatFits` flips where the shipped comparison did | **M** |
| T80 | CTA labels follow the player's LAST role | "Sponsor Again / Race" vs "Race Again / Sponsor a Race" (`SponsorHudModel.luau:36-42`) | `ResultsScreen` reads the LATCHED role (ledger OWN-D56) | **B** — legacy read the live role and flipped mid-screen |
| T81 | Persistent = the FACT, transient = the CELEBRATION | never make a fact reachable only during a transient beat (`:499-501`) | the coin chip, the standings, the CTAs and Skip are persistent regions; the fanfare lives in the slot | **M** |
| T82 | Crowd-Favorite badge never keys to placement | no P1-row star; `award.blocked` suppresses everything (`:637-656`) | shared `PromotionBadgeModel` + `ResultsParts` | **M** |
| T83 | Reduced motion ≥ the shipped surface | RM shows settled economy statically and appends award/rivalry as static rows (`:615-635`) | `ResultsScreen.luau:1019-1021` "settledEconomy" rest form | **M** |

### 1.6 HUD chrome, chips, ticker, FTUE, world omen

| # | Item | Tuned value + source | Where the presenter expresses it | Status |
|---|---|---|---|---|
| T84 | **TopbarInset ≠ physical space on notches** | the M11 lesson; `TOPBAR_SLACK = 24` (`HudZoneModel.luau:231`; `DECISIONS.md:1041`) | `init.luau:1103-1160` — the band is `topbarSafeInsets.left/top + topbarInset.x/y`, the framework env facts added for exactly this (OWN-D44), so no `GuiService` re-measure and no platform branch | **B** — the class of bug is structurally unreachable |
| T85 | Chip band placement | right of the gear, `GEAR_GAP = 12`, `RIGHT_SAFE = 8`, group natural width 300 | `GearDockModel` + `HudZoneModel` consumed directly; reserve = legacy's own `chipStripH` | **M** (with recorded intentional difference **PSD-2**: the port reserves a band below the platform strip instead of riding it, because `coreSafeContent` cannot draw inside the strip) |
| T86 | Drama dial anatomy | pivot (32,38) in a 64×44 box · fan radius 24 · 9 tangential dashes 8×5 on 20° slots · needle 3×20 · hub 10×10 · unlit at 0.7 | `StoryTokens.luau:193-230`, every number with its `SponsorGui` line, re-derived after DV-4 | **M** |
| T87 | Dial is the ZONED-SCALAR form, never the time form | dashes on a half-arc **with a needle and hub** is the discriminator (ruling (a)) | `ChipRow.luau:269-300` — needle + hub present, and no tick ring anywhere near it | **M** |
| T88 | Race chip lap read | `"Lap %d/%d"`, TextScaled in the 92×32 box (so 32, not a 14 px role) | `SponsorHudModel.luau:132` (copy) + `StoryTokens.luau:104-105` (size), after DV-7 | **M** |
| T89 | Grace chip anatomy | flag 18 @ x 8 · gap 8 · caption cap 12 · numeral cap 18, both centred and flush | `StoryTokens.luau:108-125`, four placements with their lines (DV6-1) | **M** |
| T90 | Activity ticker | last 4 plays, family stripe + chevron ORIENTATION (colour never the sole signal); rail 250 wide, entry 40, stripe 4, inset 12 | shared `SponsorTickerModel` + `StoryTokens.luau:126-132`; `Ticker.luau:34-36` | **M** |
| T91 | Ticker compact form | a max-2 strip at full safe width on a portrait phone | `StoryTokens.luau:131` `tickerCompactMax = 2` — **PROVISIONAL**, spec §12 Q2 recommendation (a), flagged not specced | **M** (recorded provisional) |
| T92 | Countdown ring / start countdown | width 126, aspect 1.3, legacy's own clamp | `StoryTokens.luau:136-137`; `StartCountdown.luau` | **M** |
| T93 | Host booth ribbon | ONE shared composite with the social banner (`§11 D-9` — the consolidation the module itself asked for); width 460, badge 30, dwell 5.0 | `MessageLayer.luau` + `FtueLayer.luau:8-13`; `StoryTokens.luau:133-135`, `:170` | **B** — legacy ships two independent trees with one recipe |
| T94 | FTUE pull dot | 10 px, clamp inset 16, flow 0.95 s; clamped to the LIST's visible band | `StoryTokens.luau:144-145`, `:172`; `StoryFlow.luau:1420-1433`, plus the port's own virtual-list case (OWN-D54) | **B** |
| T95 | Omen billboard scoping | `role == "sponsor" or isOwnKart`; rival billboards dropped (`M12_UI_FIX_SPEC.md:697-717`) | shared `OmenScope` consumed by `OmenState` | **M** |
| T96 | Omen family form cap | help opens UP, hinder presses DOWN — the colour-independent silhouette (`:771-778`) | `OmenBillboard.luau:91-102` `CAP_UP`/`CAP_DOWN`/`TAIL_POINTS` | **M** |

### 1.7 The lessons (rules, not numbers)

| # | Lesson | Where the presenter honours it | Status |
|---|---|---|---|
| L1 | **Pulses must grow from a FIXED base** (`tween-to-fixed-base.md:3-16`) — a dot once rendered at 554×554 | every beat is a motion-authority value with a declared target; nothing reads a live size and grows from it. The framework's presentation channel is a transform, never a size write | **B** — the ratchet class is unreachable |
| L2 | **Render-fed springs need BOTH dt clamps** (`spring-render-dt-needs-both-clamps.md`) | one shared solver (`motion/spring.luau`), clamped once; the presenter runs no spring math of its own | **B** |
| L3 | **Never anchor a floating element to a row that can scroll out** (`m5-xplatform-ui-input.md:74-77`) | the staging spot is the source slot's live rect (T6); the pull line clamps to the list band and falls back to RANK when the target is windowed out | **B** |
| L4 | **Every verb on every scheme; touch needs an explicit cancel** (`:46-49`) | `handleCancel` on the hand group, tap-the-armed-card-again, `‹ ›` arrows, gamepad Activate — verb×scheme matrix in spec §5 | **M** |
| L5 | **Rejections are never silent** (`:89-94`) | the optimistic record returns visibly; the toast fires with the server's own code; `CardState` gives every block a reason | **M** |
| L6 | **Clear state at the BOUNDARY, not on a tick** (`:95-98`) | `PlayFlow:endRound()` on the phase edge; the hand carry drops on `RoundGen` (OWN-D55) | **M** |
| L7 | **One zone model for HUD layout; no element positions itself** (`:111-115`) | `HudZoneModel` + the solver; zero imperative geometry in the namespace | **M** |
| L8 | **Reflow, never squeeze** (`:116-119`) | `ViewThatFits` / `Composition` lanes; §6 branches on size class only | **M** |
| L9 | **Icons must carry identity, and shape at 22 px** (`:125-130`) | `Marks.luau` — legacy's own primitive recipes, because a colour-font glyph cannot be tinted (OWN-D28) | **M** |
| L10 | **Verify a new spec actually ran, by COUNT** (`verify-spec-registration-by-count.md`) | this round: LuauUI 2752 → 2755 (+3), game 2818 → 2819 (+1); every fix additionally mutation-proved | **M** |
| L11 | **Never synthesize repro steps you didn't run** (`never-synthesize-repro-steps-you-didnt-run.md`) | every row above was verified against code this session; no row was taken from a round report | **M** |
| L12 | Studio input limits (emulator swallows injection; raw x/y dead) | recorded in `review-packet.md`; the dev-drive verbs (OWN-D52) are labelled DOWNSTREAM-ACTION evidence, not native routing | **M** |

---

## 2. Fixes made this round

**Three GAP rows closed, by three code changes** (T12, T55, T56) — all three in the band where the
port re-derived a value instead of citing one. Each ships with the smallest durable regression that
fails when the value is reverted; each mutation was run and **bit**. Items 4 and 5 below are not
extra rows: 4 is the durable half of fix 2, and 5 is the documentation debt the round also cleared.

1. **T55 / D-11 — the direct band cross now coasts** (framework, `LuauUI/src/input/autoscroll.luau`).
   Dragging from the bottom band straight to the top band cut ~490 px/s to zero in one frame. The
   decay is now a channel rather than a state: it carries `exiting` **and** the fresh `dwelling` a
   cross starts, and arming supersedes it. Three new LuauUI tests; `api.md` gains a **Coast** rule
   row; ledger **OWN-D59**.

2. **T12 — the M9 tell is back on its ratified band, in ONE home** (game). The row's stroke had
   invented `1 + 2*value` at full opacity: solid at the commit, 3 px at the land — louder at the
   start and thinner at the peak than `CommitBeatModel`'s ratified 2 → 4 px with a 0.35 → 0.0 ink
   ramp, and disagreeing with the map dot's own swell, which legacy drives from the same call.
   `TableMetrics.TELL` + `TableMetrics.tellStroke` is now the single home both consumers spend, and
   `MapCanvas`'s inline mirror of the constants is deleted. Ledger **OWN-D60**.

3. **T56 — the drag-edge scroll ARM is a semantic event** (game). The framework computed `justArmed`
   and the presenter dropped the step on the floor, so §6's one ratified feedback beat could never be
   mapped. `StoryFlow:onAutoscrollArmed()` stamps and emits `celebrate:autoscrollArmed`; the game
   maps it, LuauUI plays nothing. Ledger **OWN-D61**. Closes the autoscroll half of PS-T4 / PS-H5.

4. **T12 (b) — the two tell channels can no longer drift.** Counted with (2) because it is the same
   edit, but it is the durable half: the fix is a shared home, not a corrected constant, so the next
   change to the band moves the row and the dot together. Same shape as `TickRing` for the ring form.

5. **T57/T13 — the unported halves are now RECORDED rather than silent.** `MapCanvas` already
   documented why the blink is not ported; the row did not, and the chevron was missing with no note
   anywhere. Both now carry their reason in code and a queued row below, so a later reviewer meets a
   decision instead of an absence.

---

## 3. Queued for the director

Four value rows (T13, T15, T57, T67) plus one governance item. None can be closed without a ruling or
a design decision. Each is stated plainly with a recommendation.

**TUNE-Q1 — the in-flight tell's rising RATE (blink) is not ported.**
*Situation.* `CommitBeatModel` ramps a blink 1.15 → 2.4 Hz (power 1.6) alongside the swell, and M12
§5 names the beat "rising rate + swelling weight". The port ships the swell on both surfaces and the
rate on neither. The map ring **cannot** carry it — `UI.Path` has no per-path transparency — so
adding the blink to the row alone gives a blinking row beside a steady ring: two readings of one
clock, which is the split brain invariant 4 forbids and the same argument that produced ruling (a).
*Options.* (a) Accept as an intentional difference and log it in the parity matrix (the swell carries
the anticipation curve; `CommitBeatModel`'s own header calls the swell "the dominant ramp read").
(b) Blink the row only, accepting the mismatch. (c) Build a per-path transparency channel in the
framework so both can blink.
*Recommendation.* **(a)**, as intentional difference PSD-7. The port runs at frame rate where legacy
sampled the blink on a 250 ms tier at ~2 Hz — one flip per tick — so the channel the port drops is
the coarsest one legacy had, and the smooth swell it keeps is the one the tuning notes call dominant.
(c) is a real framework gap but it is not this beat's to pay for.

**TUNE-Q2 — the autoscroll CHEVRON affordance is not built.**
*Situation.* §6 ratifies a neutral ▲/▼ pinned to the active edge: hidden at the canvas end, 40 %
while the dwell counts, 100 % + a 0.8 Hz pulse while scrolling, 120 ms fade. Spec §7 M22's
reduced-motion row assumes it exists ("only the chevron's pulse becomes static"). Nothing renders it.
It needs two things the framework does not currently offer: the list's autoscroll signal publishes
`{ state, band }` but not *can this host still travel that way* (the honesty rule — no affordance for
a scroll that cannot happen), and there is no looped-oscillation primitive for the 0.8 Hz pulse
(springs, chases, timers and timelines all settle).
*Options.* (a) Build both framework halves, then the chevron. (b) Ship the chevron without the pulse
(state by opacity only). (c) Drop the chevron and let the moving list be the whole signal, as §6's
own first line allows ("the moving list is itself the primary signal").
*Recommendation.* **(a)**, sized as one framework row — `atEnd` on the autoscroll signal is five
lines, and a bounded decorative oscillation is a primitive M21 (the objective chip's `near` emphasis)
will need anyway. Not done this round because it is a build item with a visible design surface, not a
tuning correction, and it wants a device look.

**TUNE-Q3 — M10, the gate-slot form-entry pop, is not built.**
*Situation.* Spec §7 M10 and row-states §2 ratify a `reward` pop as a gate slot's form appears
(0.2 s Back-out), re-targeting **from the current scale** on a form change, with `play ⇄ cooldown`
explicitly one identity that does not re-pop. The port's slots appear and disappear instantly.
*Options.* (a) Build it record-driven, exactly as M16's finish flag already is: a firing on the gate
slot's FORM edge, a presentation-transform scale on a published slot path. (b) Build it mount-driven
on the `When` region's enter transition. (c) Leave it.
*Recommendation.* **(a)** — and (b) is a trap worth naming: this list is VIRTUAL, so a mount-driven
pop fires on every row that scrolls into the window, which is a pop nobody caused. (a) also gets
"does not re-pop across play→cooldown" for free, because the record is continuous. It needs a firing
seam on the roster's gate-form edges that does not exist yet, which is why it is queued rather than
fixed.

**TUNE-Q4 — the race-view toast's ×1.4 scale is not expressed.**
*Situation.* The director's own ruling (`DECISIONS.md:588`, "bigger overlay text") scaled the toast
layer ×1.4 in the race view, at y = 0.16. Half of that ruling's cause is gone: legacy scaled it partly
because the toast clipped inside the 110 px minimap, and the port's toasts are framework-scheduled at
screen level in every pose. The other half — *the text was too small to read over a live race* — is a
readability judgment that did not depend on the clipping.
*Options.* (a) Add a compact/minimized-pose metric multiplier so the toast plate and its type grow in
the follow pose. (b) Grow the toast everywhere and drop the pose branch. (c) Leave it — the plate is
already legacy's own 30/36 px box at a fixed 16 px type, which is the size the director approved for
the maximized pose.
*Recommendation.* **(b)** if the device round finds it small, else **(c)**. Flagged rather than built
because "which pose deserves a bigger toast" is exactly the kind of call the last six visual rounds
were made of, and it should be judged on a phone, not from arithmetic.

**TUNE-Q5 — three specs still say things the shipped build contradicts.**
Not a code gap; a governance one, carried from spec §11 and unresolved. `M12_UI_FIX_SPEC`'s status
line still reads "UI-SPEC gate pending" while every item in it ships (**D-6**); `UI_SPEC_avatar_badges`
§1.3 still promises a fallback badge where the build hides a nameless one (**D-8**) and enumerates six
badge surfaces where seven ship (**D-14**); `UI_SPEC_chaos_row_states` §5 still states a fixed 2 Hz
pulse that M12 §5's ramp superseded (**D-5**), and §1.1's 0.35 recede that `M12_UI_FIX_SPEC` Item 5a
superseded (**D-4**). The port builds the **code** behaviour in every case, as §11 recommends. The
ruling owed is retroactive ratification plus the four dated amendments.
*Recommendation.* Ratify `M12_UI_FIX_SPEC` as of its build date and let this audit's rows stand as the
amendment text for D-4, D-5, D-8 and D-14.

---

## 4. Evidence

| Claim | How it was checked |
|---|---|
| Both suites green | `games/RascalRally/code/run-tests.sh` → **2819 passed**, exit 0 · `GameStudio/ui/LuauUI/run-tests.sh` → **2755 passed**, exit 0 |
| New tests actually ran | LuauUI 2752 → 2755 (+3 autoscroll cases) · game 2818 → 2819 (+1 story case); the T12 pins were added inside an existing case and are mutation-proved instead |
| Every fix bites | `thickMax` 4→3 fails "the M8 wash and M9 tell are VALUE channels"; `litMin` 0.35→0 fails the same case; reverting `tellStroke` to `1 + 2*value` fails it; stubbing `onAutoscrollArmed` fails "§6: the drag-edge scroll ARM…"; each mutation was run and reverted |
| Format gate | `stylua --check src tests` clean on both trees |
| Legacy untouched | `shasum -a 256` over the 11 frozen modules diffs clean against `baseline/legacy-checksums.txt` — **11/11** |
| Ledger | framework + game rows **OWN-D59…D61** in `responsibility-ledger.md`; `api.md`'s `newAutoscroll` table gains the **Coast** rule |
