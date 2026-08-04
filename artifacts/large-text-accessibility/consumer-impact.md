# Rascal Rally consumer-impact ledger — large-text-accessibility (Step 8.5)

Status: DONE 2026-08-03 (audited at stage close; the one owed follow-up is §C, the legacy racer item HUD).

## Changed LuauUI contracts and their game consumers

| Contract change | Kind | Game consumers affected | Action |
|---|---|---|---|
| `preferredTextOffset` now measured (Large 6→4) + confirmed via `GetTextSizeOffsetAsync` + live `PreferredTextSize` subscription (src/client/roblox_env.luau, src/client/preferred_text.luau) | Compatible behavior fix (adapter-internal; env fact unchanged in shape) | Every mounted Sponsor surface reads the fact transitively; `TableMetrics`/`table.luau` row heights consume it | No caller edit expected; game-side compatibility test asserting Sponsor rig solves at offsets {0,4,10,14} + hot swap; Studio canary |
| `UI.Text` gains construction-only `disclose` (package A) | Additive public prop | Identity/secondary one-line cells: RacerList name, FollowScreen watched name, HandDock card captions, Ticker target, Results standings/seat names, sponsor chips, award reason | Adopt `disclose = true` on identity/flavour truncating labels after the fixture sweep confirms each (LT-11/LT-12) |
| `text.fit`/`text.size` gain `offset` spec field (planned, Fable) | Additive spec field | `RolePickScreen.textFit` (game-local glyph math, box-fit CTAs — live truncation at Largest observed in probe session: secondary CTA "Sponsor a…") | Replace game-local fit math with LuauUI `text.fit` passing the live offset; call sites become offset-reactive |
| Dump schema bump luauui-dump/2 with per-text-node truncation report (package A) | Additive verification surface | Game tests/scenario reports that parse dumps (check for schema pins) | Audit game tests for schema-string pins; update if pinned |

## Live findings to fix game-side (recorded during stage)

1. **RolePickScreen secondary CTA truncates at Largest** (observed live 2026-08-03,
   real preference stepped through the in-experience menu; production LuauUI role
   pick). Cause hypothesis: `RolePickScreen.textFit` computes an explicit px size
   from a 240x52/44 box with game-local glyph-em math, blind to the +14 paint
   offset; painted glyphs exceed the box and TextTruncate ellipsizes an ACTION
   label. Fix: framework-owned fit with the offset subtracted (see contract row
   above); deterministic fixture must reproduce before/after.

## Spec reconciliation owed (LT-12, recorded as LTN-3 when corrected)

- `UI_SPEC_sponsor_luauui.md` S16.13 lists countdown, coin total/gain, CTA label,
  section heads under "what truncates" — all essentials under §8's own Step 8.5
  ruling; correct to reflow/scroll paths once fixture evidence is in.
- §8 "Truncates (one line)" lists position numeral and lap text — required facts;
  their boxes must reserve to measured content at every offset instead.

## Rascal Rally consumer work — DONE 2026-08-03 (game suite 3029 → 3067, 0 failed; verified independently by the lead: 3067 passed, 0 failed)

### A · `UI.Text{ disclose = true }` adoption — 12 identity/secondary one-line labels

RacerList `Name`; MapCanvas `TagText`; FollowScreen `WatchedName`; HandDock
`CardName`/`GhostName`/`ShowLabel`; Ticker `TargetName`; ResultsScreen `Name`
(standings)/`SeatName`/`RivalTag`/`SponsorChip`/`AwardReason`. Deliberately NOT
declared (LTN-3: required facts that must never truncate, now asserted not to):
`Pos`, `Place`, `WatchedPos`, `LapText`, `GraceCountdown`, `CountdownNumeral`,
`LedgerCoinTotal`, and the wrapping reasons (toast/caption/ribbon/recap/bait/
tease/human/omen).

### B · The role-pick fix (the live "Sponsor a…" defect)

`RolePickScreen.textFit` gained an optional paint-time `offset` (both bounds
subtract it); `preferredTextOffset` threads from the env as a Readable inside
the same memo `sizeClass` rides. Pre-fix at Largest: 356x50 of ink in 240x44 of
box (the ellipsis observed live). Post-fix the painted size fits both axes at
every preference; Medium byte-identical (asserted). Verified RED-FIRST by the
implementing agent (unwiring the offset fails the pin).

### C · Every other game `text.fit`/`text.size`/scaled-arithmetic caller audited

ResultsParts `fitType`/`heroType`/`fitWidthType`/`numeralWidth` — offset-aware.
TableMetrics `mapTagType` + new `markSize` (44px minimize dash + watch chevrons
— truncated from Large up pre-fix), StartCountdown `numeralType` — offset-aware
via one stated rule (`TableMetrics.paintOffset`). NOT changed: HudZoneModel
`itemCaption`/`itemNameFlash` — their caller is the legacy Instance-painting
RACER item HUD (`ItemFx.luau`) with no LuauUI environment; **owed follow-up: a
preferred-text seam for the legacy HUD or migrating the item pill to LuauUI**
(its caption already has a legibility floor + icon-first fallback).

### D · Cap/box corrections (each spec-cited; offset-0 changes recorded)

1. RolePick sub-lines wrap 2 → 3 (card grows; §9 grants it).
2. **Toast pill width FILL → CONTENT — a shipped, offset-independent defect:
   every toast solved 20px wide with a 0px reason** (existing tests asserted
   string/tone/plate, never the box).
3. Toast pill height fixed → floor (short toasts byte-identical).
4. Toast reason lines 2 → 4 (longest shipped sentence needs 3 at Larger).
5. Results ledger section heads 1 line ellipsized → 2 lines whole (LTN-3.1).
6. Results recap `full` 2 → 4 lines (54-char tally wanted 3 at Medium already).
7. `ledgerBodyHeight`/`standingRowHeight` literals + one painted line box (coin
   pill overflowed by up to 14px, standings rows by 5px at Largest).

### E · Recorded findings for the director / follow-ups (measured, asserted,
deliberately not fixed here)

1. Map name-tag: painted name stands ~11px proud of the ratified 72x18 plate at
   Larger+; name reachable via disclose; plate growth is a director call.
2. Racer row on 667x375 wants 17px more than the list lane gives at EVERY
   preference incl. Medium — pre-existing, offset-independent.
3. ~~The recap's REDUCED one-line form still ellipsizes on the two narrow sponsor
   rows; raising it makes the composition report NO legal arrangement at
   635x233 — worse. Non-interactive span, disclose cannot attach.~~
   **CLOSED 2026-08-04**: the reduced form declares LuauUI's `reveal = "auto"`
   (LTN-8, the director-ordered auto-scroll) — the whole tally slides through
   the line on the framework presenter's tick; the results sweep's recap
   allowlist is gone and the E·3 pins flipped (see the marquee section below).
4. 667x375 above Large has no legal arrangement — the composition shows its
   declared `column` fallback and names the rejection. Which regions may
   scroll/drop at raised preferences is a director decision (§S16.5).
5. FRAMEWORK: a content-hugging `minMax` box measures children at the OFFER and
   clamps width after, so cross-axis height is reserved for the pre-clamp
   width. Reported to LuauUI as a follow-up (visible on any hug-with-cap whose
   offer exceeds the cap).
6. Dead code: `ResultsScreen.messageContent` unreachable + would error (A50
   leftover). Untouched.

## Verification (to be filled with exact commands/results)

- [x] Game suite (`games/RascalRally/code/run-tests.sh`, NO arguments): 3067 passed, 0 failed (baseline 3029) — run by the implementing agent AND re-run by the lead at the final source
- [x] Game contract tests: tests/luauui_large_text_contract.spec.luau (lead) + tests/luauui_large_text_sweep.spec.luau (22 cases) + tests/luauui_large_text_results.spec.luau (16 cases) + tests/lib/luauui_text_probe.luau, all registered
- [x] Both Rojo project mappings valid (project_parity.spec green)
- [x] Sponsor Studio canary, driven half: REAL-setting Medium->Largest->Medium with production surfaces mounted (role-pick regression dead, table/chips whole) + exact 667x375 at Largest, all in studio/large-text.json
- [ ] Sponsor Studio canary, owed half: compact-phone EMULATED sponsor rows (covered headless + by the physical phone pass; see the artifact honestBoundary)

## Director round (2026-08-03, post-gate live review) — five findings + two rulings

Findings (all fixed, all game-side; framework untouched this round):

1. Finish flag "…" in the 22px status swatch → `TableMetrics.chipTextSize`
   (painted-constant, floor 1) via `RacerList.statusGlyphSize`.
2. Racer-row slack ("name cut off … then empty space") → THREE parts:
   `stripReserve` (134 → true content max 106 at offset>0), the live-measured
   Pos void (20px box ellipsized "P6" to NOTHING at Largest — the headless
   measurer reads the heavy face ~1px narrower than the engine, which is why
   the LTN-3.2 sweep pin stayed green), and then the ruling below deleted the
   Pos cell entirely. Name box 162 → 220 at Largest, measured live.
3. Finish-countdown overflow under the "Finishing!" chip → ChipRow painted-
   constant sizes (`chipText` memos over the five band sizes).
4. "Sponsor a Race" type stays small → secondary adopts the primary's derived
   size (finding-4 first cut: two-line wrap), then AMENDED by ruling A41.
5. Lap text overflow → same ChipRow painted-constant family as (3).

Rulings:

- **Pos numeral retired** ("we know their places based on where they are in
  the list") — cell deleted, 30px to the name, supersedes LTN-3.2's row-numeral
  reserve-to-fit (which now binds the watched position / lap text / any future
  rank numeral). Recorded finding E·2 (667x375 row 17px overflow) RESOLVED by
  the freed room — its pin flipped to a regression guard.
- **A41: the role modal widens, never wraps, where the screen has room** —
  `ctaWidthFor` on A40's size-class seam; both CTAs one shared width, secondary
  one line at the shared size; compact keeps the wrap; Medium byte-identical.
  Verified live at Largest: both buttons 374x52, shared authored 29.

Suite after the round: 3069 passed, 0 failed. Live evidence: role modal +
sponsor table at real Largest in the RR place (this session).

## LIVE FINDING (2026-08-03) — ✅ FIXED FRAMEWORK-SIDE 2026-08-04:
## the FollowScreen cycle buttons paint their FULL label live, at EVERY preference

**RESOLUTION (2026-08-04).** Root cause was NOT the label write or the verdict:
`applyCompactLabel`'s minimal-write cache (`lastCompact[path]`) survived the
Follow region's structural remount, so the RE-created buttons (born with their
full labels) never got the swap re-applied — one mount looked right, every
remount after it did not (which is why every single-mount headless witness was
green). Fix: `renderer.structuralSync` now clears `lastCompact` in the same
removal block every other per-path cache dies in. Pins: framework
`compact_label.spec` "a REMOUNTED button gets its verdict re-applied"
(mutation-verified) + game `luauui_sponsor_table.spec` "the ‹ › GLYPHS survive
a pose-toggle remount". Verified LIVE in the production place: minimize →
restore → minimize now paints ‹ › on the remounted buttons. Lesson:
`docs/lessons/a-per-path-cache-outlives-the-node-it-remembers.md`. Suites:
LuauUI 3292 / game 3071. Original finding text below for the record.

Measured in the production RR place (Play Solo, sponsor minimized pose):
`CyclePrev`/`CycleNext` TextButtons paint "Previous racer"/"Next racer"
ellipsized to "…" in their 44px boxes — at Medium (sz 32), Large (28) and
Largest (18): the `markSize` seam tracks the preference correctly, but the
`compactLabel` TEXT swap ("‹"/"›") never reaches the live instance. The SAME
build headless (sponsor rig, offset 14, minimized) paints `label = "‹"` — so
the solver's compact verdict machinery works headless and the divergence is in
the live render path. Engine measure is sane (GetTextBoundsAsync "Previous
racer"@32 = 191px » 44). `screen_target` documents the text form as "just a
shorter string on the ordinary label write" — the suspect seam is that write
(or the verdict reaching the live renderer at all). NOT offset-caused (broken
at Medium too) — but it violates §8 "an action label may never ellipsize" and
the compactLabel stage's own device-verified behavior (2026-07-27), so a
regression landed somewhere after that verification. Priority: HIGH, next
session — needs a live-path trace (renderer drawnButtonText → setProp label →
screen_target Text write), not more headless pins, since every headless
witness is green while the live place is wrong.

## Cleanup round (2026-08-04, director: "are there other hard-coded sizes we
## should be cleaning up") — three more fixed text boxes become floors

Audited every fixed-px box in the sponsor UI. Kept fixed on purpose: art/target
boxes (swatches, pills, minimap, 44px targets — reservation is the feature) and
the platform-capped painted-constant bands (topbar chips, status swatch — a
product compromise, recorded). Fixed this round (all legacy-floored, Medium
byte-identical, growth = line count × `TableMetrics.lineGrowth`):

1. **Watched card 260x60** — "P1" painted ~17px PROUD of the plate at Largest
   (visible in the GO! capture). `TableMetrics.watchedCardReserve` (+2 lines),
   FollowScreen `cardHeight` opt.
2. **Showstopper caption strip 12px** — caption painted 26px in the 12px band
   at Largest. `TableMetrics.cardLabelReserve` (+1 line), HandDock
   `labelHeight` opt.
3. **Role-pick primary CTA height 52** — fits at Largest with 0.4px to spare
   (the near-exact-box class that painted "2…"). Now a floor via the same
   memo family as the secondary; solves to exactly 52 at every shipped
   preference — a dormant safety net.

Pins: sweep spec "the watched card and the Showstopper strip are FLOORS" —
arithmetic (byte-identical at 0/nil/garbage, +g/+2g at 4/10/14) + minimized-
pose containment of both watched lines on every view at every offset + the
strip's height equals its reserve exactly (12 at Medium). Suite 3072. Live: VERIFIED AT REAL
Largest in the place (2026-08-04, Studio access restored): card height solved
to exactly the 94 px reserve (60 + 2x17), name and "P2" both inside the plate,
cycle chevrons painting, and the "Finishing! 10" grace chip whole in the same
capture. Medium also verified (card exactly 60). Preference restored to Medium
after the drive.

Still open (director calls, unchanged): the map name tag 72x18 at Larger+
(grow plate / lower floor / drop tag) and which 667x375 regions may scroll
above Large (§S16.5).

## Director visual round 2 (2026-08-04) — map tag inversion, ledger alignment,
## plate clamp-follow, marquee direction

1. **Map name tag** (closes recorded finding E·1): type-first redesign —
   `mapTagTextSize` 20 stated, plate derived (`mapTagReserve`, floor 72, glyph
   budget 8), dot 14→18. The old `mapTagType` shrink rule + `MAP_TAG_MIN_TEXT`
   deleted. Tag overflow pin flipped to "none at any preference".
2. **Results ledger row** aligns by the bottom (`align="end"`): measured live at
   Largest, a wrapped "Rally Points" label pushed the bar a line below the coin
   pill under top alignment. New pin: bodies level on every view at every
   offset, both forms.
3. **FRAMEWORK: disclosure plate clamp now FOLLOWS** (presenter
   `clampDisclosure`, re-run per tick): live async text measure grew the plate
   past the one-shot clamp — the "Tailwind" plate hung off the screen bottom.
   Same live-async-vs-headless-sync class as the compact-label remount bug.
   New framework pin: clamp follows after-mount geometry changes.
4. **Marquee direction recorded** (supersedes LTN-2 for the recap): the
   finish-screen recap's reduced form will auto-scroll instead of ellipsizing;
   LTN-2's full constraint list binds; scoped as its own framework mission.
   Recorded finding E·3 (reduced recap ellipsis) stays open until it ships.

Suites: LuauUI 3293 / game 3073.

## The marquee mission SHIPS (2026-08-04) — E·3 closed + the role-pick size pop

1. **FRAMEWORK: `UI.Text{ reveal = "auto" }` (LTN-8)** — the auto-scrolling
   one-line reveal, built to LTN-2's full constraint list (the decision packet
   has the line-by-line account; `tests/text_reveal.spec.luau` pins 13 cases:
   declaration/enum, `truncate+reveal` facts + `naturalWidth`, the full
   rest→out→end→back cycle with maxTravel == distance, fits/undeclared
   negatives, re-solve and dismiss retire, reduced-motion both ways, one-strip
   + `movingText` allowance, plate-outranks-strip). New renderer seam:
   `controller.setPaintHeld(path, held)` (presentation-only visibility hold
   for the covered source). A reveal node is also a disclosure source.
2. **GAME: the recap's reduced form declares it** — one prop on
   `ResultsScreen.recapForm`'s `RecapLine`; the span form untouched. E·3 pins
   flipped in `tests/luauui_large_text_results.spec.luau` (reveal declared +
   a live strip over the mounted 667x375 sponsor surface + reduced-motion
   parity) and the clippedEssential sweep dropped its recap `nonEssential`
   allowlist — the audit accepts the declaration itself now.
3. **GAME: the role-pick first-present size pop** (director: "text around the
   sponsor button pops in size") — the modal painted from DEFAULT onboarding
   flags and re-derived when the server's DataStore-delayed mirror write
   landed (measured pre-fix: "Sponsor a Race" @27 → "Cause Chaos" @35; CTAs
   374 → 294 px at Largest). Fixed by the ledger's own rule: `SemanticModel`
   publishes `onboardingKnown` (attribute existence), `roleModalUp` holds the
   present until the fact is real; first-ever known-false flags present at
   boot unchanged. Pins in `luauui_sponsor_entry.spec.luau`; the rig's default
   player now carries known-false flags, `player = {}` = write in flight.
   **SECOND CAUSE, caught by the director's textpop.mov after the first
   shipped** (the clip's copy never swaps — the flags hold held; the SUB row
   re-wraps two lines → one and widens = the size CLASS flipping): the camera
   reports a **1x1 viewport on the first client frame** (boot watcher: 1x1 at
   0.693 s, real at 0.779 s), so a presentation constructed inside that window
   derives `compact` from one pixel — visible on the device emulator, whose
   slower boot lets the modal paint inside the window. FRAMEWORK:
   `environment.set` now refuses a viewport write without two real >1px axes
   (an engine placeholder is not a fact — the `interactionClasses` precedent;
   pinned in `tests/adaptive.spec.luau`). GAME: the client bootstrap waits for
   a real `camera.ViewportSize` before constructing either Sponsor
   presentation (a wait on the fact, never a duration; source pin + mutation
   test in `edge_case_hardening.spec.luau`).

4. **LIVE-FOUND during the Studio drive, fixed same-session (the F-1 class
   again):** a losing arrangement candidate keeps its mount, rects AND
   truncation facts — only visibility knows it does not paint. Dropping the
   real preference Largest → Medium flipped the recap composition to the rich
   form; the reduced line went hidden and the strip kept travelling over it.
   The presenter's tick verify now re-reads `hiddenRoots` exactly as it
   re-reads the facts (framework pin: "a source that goes HIDDEN mid-flight
   retires the strip", ViewThatFits fixture, red-first). 14 reveal pins total.

**Suites: LuauUI 3307 / game 3075.** Live Studio verification (2026-08-04,
production RR place, real preference stepped through the in-experience menu
both ways):

- **Largest** — reveal strip mounts over the reduced recap on the held
  results-sponsor scenario, travels at the derived ~63 px/s, pauses, returns,
  and rests as the ellipsis with the source paint back (capture:
  mid-travel tail visible, head clipped clean). Role modal presents born with
  its final copy at the shared 29 px CTA size — frame-by-frame watcher shows
  textSize constant from the first painted frame (the only motion is the enter
  transition's scale). Onboarding attributes existed (false/false) at present.
- **Medium** — the composition picks the rich recap form (whole, one line,
  TextFits=true), the hidden reduced candidate stays hidden, and NO strip ever
  mounts over a 6-second watch. Role modal at the byte-identical A27 numbers
  (43/27/19 at 240x52/44), stable from first paint.
- Preference restored to **Largest** after the drive (the director is
  actively reviewing large text).
