# Parallel Sponsor (Step 6) — acceptance ledger

**Date opened:** 2026-07-30 · **Stage:** `parallel-sponsor`
**Sources of truth:** `games/RascalRally/docs/LUAUUI_SPONSOR_PARALLEL.md`
(full parity matrix), `GameStudio/ui/LuauUI/docs/plans/agent-execution-contract.md`
(evidence ladder E0–E5, status vocabulary), `studio-device-verification.md`
(five-view matrix), the ratified Sponsor UI specs under
`games/RascalRally/docs/ui/` and `docs/missions/M12_*`.

**Status vocabulary** (contract §2): `OPEN` (not yet attempted) ·
`PASS_AUTOMATED` · `PASS_PHYSICAL` · `PASS_HUMAN` · `FAIL_PRODUCT` ·
`FAIL_ENVIRONMENT` · `PENDING_PHYSICAL` · `PENDING_HUMAN`. A row never passes
through a different, easier row; captures and traces must pair (neither alone
proves parity). "Looks similar" is not a verdict; every closed row records
`legacy evidence + LuauUI evidence + known difference + verdict`.

**Shared drivers** (named once, cited by rows):

- `D-scn` — the shared scenario protocol (`LuauUIScenarioAPI` surface extended
  with the Sponsor parity scenarios; same fixtures drive legacy and LuauUI,
  only one presenter mounted per run).
- `D-matrix` — five-view Studio device matrix driver
  (`tools/studio/device_matrix.luau`): compact-phone-portrait,
  compact-phone-landscape, tablet-landscape, desktop-standard,
  console-ten-foot.
- `D-suite` — `games/RascalRally/code/run-tests.sh` and
  `GameStudio/ui/LuauUI/run-tests.sh`.
- `D-trace` — command/side-effect trace recorder exported per fixture run.
  Watches ALL sponsor-relevant remotes, not just `SponsorCmd`: the frozen verb
  table (`games/RascalRally/docs/luauui-sponsor-command-shapes.md`) shows only
  `play`/`role` ride `SponsorCmd`; watch-focus intents ride `WatchFocus`
  (init.client:1182/1207) and `WatchPark` (InputBridge:246); pose/skip/dismiss
  are client-local. Duplicate-command rows (PS-L6) count all three remotes plus
  binding/resource counters and feedback events.
- `D-phys` — physical-device procedure recorded in `review-packet.md`.

Evidence lands in `rows/PS-*.json` + `captures/` named
`<row>-<fixture>-<device>-<orientation>-<state>.png`, per the existing
artifact schema.

---

## PS-B · Baseline freeze (build sequence step 0)

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-B1 | Legacy Sponsor modules unchanged all stage; selector isolated to one startup branch | Silent drift into legacy while "building parallel" | E1 checksum diff | `baseline/legacy-checksums.txt` re-run | **PASS_AUTOMATED** (recorded at freeze; re-checked at gate) |
| PS-B2 | Both suites green at freeze | Regressions blamed on later work | E1 | D-suite | **PASS_AUTOMATED** (RR 2425 / LuauUI 2591, 2026-07-30) |
| PS-B3 | Pinned legacy captures+geometry: table min/max poses, hand dock, HUD, results both roles, on all five views | Parity judged from memory instead of a frozen bar | E3 | Studio session vs legacy build; D-matrix | **PASS_AUTOMATED 2026-07-30 (rig-held sweep)** — legacy captured at ALL FIVE device rows max pose + phone portrait/landscape min pose + armed state + sponsor results both phone orientations (`rows/PS-B3-legacy-*.png`, `PS-C1-armed-hand-legacy-*.png`, `PS-R1-legacy-results-*.png`), every state held by the shared rig (no auto-advance). Racer-role results still owed (needs a racer-role session). Paired LuauUI counterparts live beside them |
| PS-B4 | Pinned legacy input traces: pointer drag→commit, arm/tap flow, cancel, illegal-drop toast | Feel compared against recollection | E3 | Studio session, D-trace | **PARTIAL 2026-07-30** — `baseline/studio/PS-B4-input-trace-legacy.md`: arm→tap→commit traced end-to-end, exactly one `play` server receipt (command shape frozen). Injected pointer-drag promotion impossible (instrument limits recorded in that file); drag-path traces stay with the deterministic protocol drivers + physical rows |
| PS-B5 | Characterization tests pin shared-model outputs at the semantic boundary before any adapter refactor | Adapter extraction silently changes meaning | E1 | D-suite (new specs) | OPEN |

## PS-L · Entry, role, lifecycle

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-L1 | Boot and late-join land in the correct Sponsor state | Race conditions only at boot; fixture-only paths | E1 + E3 | D-scn boot/late-join fixtures | **PARTIAL 2026-07-30** — boot proven live (`rows/PS-L1-L6-entry-lifecycle-live.md`); auto-seat/reconnect headless; live multi-client late-join owed (StudioTestService row) |
| PS-L2 | Role selection modal; exit always reachable | Focus trap; unreachable cancel on one input class | E1 + E3 | D-scn role fixture + D-matrix | **PARTIAL 2026-07-30** — Navigate/Activate-once/modal-held proven live; mandatory-modal Cancel-no-op via new framework `cancelPolicy="none"` (6 LuauUI tests); gamepad-B + outside-tap = PENDING_PHYSICAL (VirtualInput refuses ButtonB) |
| PS-L3 | Full phase arc: start→live→grace→results→rematch→reconnect→teardown | A surface leaks across a phase boundary | E1 + E3 | D-scn phase-arc fixture | **PARTIAL 2026-07-30** — grace/results/racing arc held+followed live, depth stayed 1; rematch/reconnect live rows owed with results layer |
| PS-L4 | Passive HUD over gameplay vs engaged table/modal responder ownership | Engaged UI steals gameplay input, or passive UI eats taps | E3 | D-scn + input probes | **PARTIAL 2026-07-30** — engine selection nil while engaged + passive→engaged edge proven live; touch/gamepad ownership = PENDING_PHYSICAL |
| PS-L5 | Repeated mount/unmount + role churn leaves zero duplicate bindings, scopes, resources, remotes, lingering UI | Leaks invisible in one pass | E1 + E3 counters | D-scn churn fixture, D-trace | **PARTIAL 2026-07-30** — headless: 10-lifetime churn zero-residue + exactly-one-command; 25-cycle registry-neutral; live churn rerun owed once interactive layers land |
| PS-L6 | Exactly one presenter mounted; selector teardown-before-remount; ONE authoritative command per intent | Double side effects (plays, sounds, analytics) | E1 + E3 | D-trace duplicate-command assertion, both selector states | **PARTIAL 2026-07-30** — selector exclusivity + one-mount PROVEN LIVE both flag states (`rows/PS-L6-selector-live-proof.md`); headless churn spec green; owed: live duplicate-command trace + live churn with the first interactive layer |

## PS-T · Director table and racer list

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-T1 | Minimized/maximized poses; landscape/portrait map⇄list splits; safe-area docking | Reflow squeezes instead of restructuring | E3 | D-scn table fixtures × D-matrix | **PARTIAL 2026-07-30** — five-view sweep both poses w/ captures + class/axis verdicts (`rows/PS-T-table-list-live.md`); selection survived a live axis flip; OPEN findings: watched-card anchor wrong, white chip unattributed, split-axis keying at extreme aspects needs ruling; legacy-paired sweep owed |
| PS-T2 | Live roster order changes keep stable row identity | Rows remount/flicker on position swap | E1 + E3 | D-scn roster-churn fixture | **PASS_AUTOMATED 2026-07-30** — headless identity specs + 12 s live re-sorts with stable selection/watch/mount counts |
| PS-T3 | Scroll/virtualize/clip; map/list coordination; focus keep-visible | Offscreen focus; clipped rows; scrollbar overlap | E3 | D-scn + D-matrix | **PARTIAL** — headless windowing at 12 rows; live bench caps at 8 karts (no window) — live keep-visible/window rows owed via a >8 fixture or pad navigation session |
| PS-T4 | Drag-edge autoscroll, dwell, cancel; reorder while a card is in flight | Autoscroll fights reorder; ghost drifts (pointer-rect lesson) | E1 + E3 | D-scn drag fixtures, D-trace | OPEN (autoscroll model instantiated in L2; drag sessions arrive with L3) |
| PS-T5 | Row states with ratified precedence; never color-only | Precedence inverted; a state silently unexpressed | E1 + E3 | D-scn row-state fixture (all states forced) | **PARTIAL 2026-07-30** — full precedence matrix headless (46-case spec); live greyscale proof for finished/active forms; blocked/slash/disconnected live fixture pass owed |
| PS-T6 | Map dots, names, omen rings, family color, avatar ownership, live target chasing | Dot desync (server-pose lesson); ring form drift | E3 | D-scn minimap fixture | **PARTIAL 2026-07-30** — dots live w/ ≤100-pt trace, 44px hit floors, tap-to-watch once-only proven; omen ring form arrives with PS-W; avatar ownership with L4 |

## PS-C · Cards and input

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-C1 | Hand, energy, Showstopper gates; armed/tap flow; drag flow; cancel; fly-home; commit; pending; land; blocked; rejected | A state renders but its transition is wrong; pending treated as success | E1 + E3 | D-scn card fixtures (each state forced + each transition driven) | OPEN |
| PS-C2 | Velocity handoff and interruption per `UI_SPEC_sponsor_motion.md` | Hard-cut at release; uninterruptible flight | E3 trace of positions/velocity | D-scn drag+release fixtures | OPEN |
| PS-C3 | Legality from the shared model only; blocked rows skipped by navigation; ONE correctly keyed toast per invalid attempt | Presenter re-derives legality; toast spam | E1 + E3 | D-scn illegal-play fixture, D-trace | OPEN |
| PS-C4 | Paradigm adaptation: direct drag where pointer-appropriate; deliberate arm/edit/adjust for gamepad/keyboard/touch needs | A verb missing on one scheme | E3 (Studio-drivable schemes) + E4 (touch/gamepad) | D-scn × input axes; D-phys | OPEN |
| PS-C5 | Mouse+keyboard, touch, gamepad/ten-foot, hybrid mid-session switches: no duplicate or unreachable action | Hybrid switch double-binds or orphans a verb | E3 + E4 | D-scn hybrid fixture; D-phys | OPEN |

## PS-H · HUD, story, feedback

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-H1 | Lap/drama/topbar composition; narrow-device reflow | Topbar inset ≠ physical space on notches (M11 lesson) | E3 | D-scn HUD fixture × D-matrix | OPEN |
| PS-H2 | Objective pill visibility, ring, docking; guaranteed absent in results | Pill leaks into results | E1 + E3 | D-scn phase-arc fixture | OPEN |
| PS-H3 | Ticker, captions, social/host banners, toasts: stacking + priority rules | Two surfaces claim the same slot; priority inversion | E1 + E3 | D-scn feedback-burst fixture | OPEN |
| PS-H4 | Choreography beats: commit, land, row wash, impact, cascade, bank, Showstopper, finish, award, results | Beat timing/causality drifts from legacy feel bar | E3 paired capture+trace vs PS-B4 | D-scn beat fixtures | OPEN |
| PS-H5 | Sound/haptic semantic events fire on their causal frames; content stays game-owned | Event on wrong frame; asset choice migrating into LuauUI | E1 + E3 | D-trace onFeedback log | OPEN |
| PS-H6 | Reduced-motion equivalents preserve information (never just delete beats) | RM deletes meaning; or motion sneaks past the policy | E1 + E3 | D-scn fixtures × reducedMotion axis | OPEN |

## PS-W · World omens

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-W1 | Omen billboard scoping, first-encounter teaching, timing ring | Billboard outlives scope; ring form breaks the one-timer invariant | E2 + E3 | D-scn omen fixture (billboard_target seam) | OPEN |
| PS-W2 | Minimap omen behavior matches world state | Map and world disagree | E3 | D-scn omen fixture | OPEN |

## PS-R · Results (both roles)

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-R1 | Racer and Sponsor results, portrait and landscape | Role×orientation cell never actually rendered | E3 | D-scn results fixtures × D-matrix | **PASS_HEADLESS 2026-07-30, RE-OPENED AND RE-PASSED 2026-07-31 (fix round 3)** — round 2's Studio captures found the surface composed over a still-mounted table (N1), an empty standings band (N2), a hero line contradicting its own recap (N5), inverted CTA emphasis (N6) and an unlabelled Skip (N7); all five closed with regressions. **BOTH round-2 BLOCKERS (N1, N2) FIXED AND VERIFIED LIVE** in `rows/C2-results-sponsor-rawpane-portrait.png` (sponsor role, portrait): the table is TORN DOWN under the surface (nothing behind results paints text — N1), the standings band is POPULATED (1st Razz / 2nd Wrenchy / 3rd Bolt, under the recap — N2/PSD-1), the hero line sits over a NON-ZERO recap ("1 pass created · 1 recovery sparked · Drama Score 54" — N5), "Sponsor a Race" is the BRIGHT primary with "Race Again" muted (N6), and Skip is LABELLED mark-plus-word (N7). Still owed: the rest of capture C2 — racer role (never captured on either build) and both landscape cells. Original note: — `luauui_sponsor_results.spec` renders BOTH roles on five fixtures (388x762 / 812x375 pinned phones, 390x844, 844x390, 1920x1080). The ROLE VARIANT is now the spec's, not legacy's: racer = placement slam, sponsor = round-story hero line, and a sponsor with no signature moment gets no hero band instead of legacy's meaningless "8th!". Studio row still owed |
| PS-R2 | Spotlight sequence, standings, economy/Rally Points, skip, persistent action bands | Skip races the choreography; points mis-sourced | E1 + E3 | D-scn results fixtures, D-trace | **PASS_HEADLESS 2026-07-30 (L6); the round-2 blockers on this row's own surfaces FIXED AND VERIFIED LIVE 2026-07-31 (fix round 3)** — `rows/C2-results-sponsor-rawpane-portrait.png` shows the persistent bands doing their job on the shipping path: the coin chip (`1460 +220`) and the standings are persistent FACTS under a torn-down table (N1/N2), the CTA band carries the mode's own verb as its bright primary (N6), and the Skip affordance is a LABELLED mark-plus-word chip at the 44 px floor (N7) rather than the two-square glyph round 2 measured. Owed with C2: the same proof for the racer role and for landscape. Original note: — one piece at a time in the authored order (economy → award → payoff), driven by the REPLICATED tail clock `(tick - phaseTick) / tickHz`; all three skip affordances collapse the schedule to the same settled rest state through ONE gate; the coin chip and standings are persistent facts, the fanfare transient. A blocked award celebrates nowhere; a late roundStory splices idempotently |
| PS-R3 | CTA stacking, safe areas, scrolling, focus order; all facts reachable; zero overlap on pinned small phones | The M10/M12 small-phone overlap class returns | E3 | D-matrix compact rows | **PASS_HEADLESS 2026-07-30 (L6)** — `ViewThatFits` picks the column on both pinned phones and the row on regular/wide; `HudZoneModel.findOverlap` over the solved band rects is clean on all five fixtures × both roles with the fullest payload; every CTA and Skip clears 44 px; the standings band clears the shipped 60 px floor everywhere; a pad reaches the live candidate, the standings scroll and Skip, and NEVER the hidden candidate (framework fix OWN-D35). Safe area is the framework's (`deviceSafeContent`), not hand-measured. Studio row still owed |
| PS-R4 | Phase-boundary transition holds minimum dwell; no race-only surface visible in results | Dwell skipped under churn | E1 + E3 | D-scn phase-arc | **PASS_HEADLESS 2026-07-30 (L6)** — a payoff piece whose window runs past the routine profile's 5 s RESULTS phase keeps showing across the RESULTS→INTERMISSION edge while the standings band swaps to the roll-call underneath it; the skip latch is tail-scoped and survives the same edge. The surface mounts on `phase == "results"` and exits INSTANT by M23's declared asymmetry — a dwell guard on the MOUNT would contradict that ruling, so the floors live in the tail clock instead |

## PS-I · Content and inclusion

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-I1 | Every player-facing string from existing localization sources; proper nouns preserved | Hardcoded copy sneaks in | E1 source scan + E3 locale axis | D-suite + D-scn locale fixture | OPEN |
| PS-I2 | Avatar placeholder/success/failure/stale-rejection; NPC vs human identity parity | Stale async resurrects a released avatar | E1 + E3 | D-scn avatar fixtures (forced failure/stale) | OPEN |
| PS-I3 | Preferred text, ten-foot, transparency preference, contrast, hit floors, keyboard occlusion, never color-only | A floor silently unmet on one view | E1 (token gates) + E3 axes | D-scn × preferredText/transparency axes, D-matrix | OPEN |
| PS-I4 | Roblox preferred text size applied exactly once | Double-scaling (audit-corrections §9) | E2 + E3 measurement-vs-paint | dedicated probe fixture | OPEN |

## PS-P · Reliability and performance

| ID | User-visible behavior | Risk | Evidence | Driver | Status |
|---|---|---|---|---|---|
| PS-P1 | Repeated open/close, rapid input, phase churn, late async, reconnect, missing assets, malformed/partial state: no breakage | Fixture-only happy paths | E1 + E3 | D-scn failure fixtures | OPEN |
| PS-P2 | No stale completion resurrects released content | PreloadAsync logical-cancel misunderstood | E1 + E3 | D-scn stale-async fixture | OPEN |
| PS-P3 | Frame time, instance count, memory, layout work, input latency within agreed budget on weakest device | Studio numbers passed off as device numbers | E4 | D-phys weakest device | OPEN → will end PENDING_PHYSICAL |
| PS-P4 | Large rosters and dense celebration bursts stay bounded | Unbounded per-frame work under bursts | E1 + E3 (Studio regression numbers, labeled) | D-scn stress fixtures | OPEN |

## PS-G · Specialist, verifier, human gates

| ID | Gate | Evidence | Status |
|---|---|---|---|
| PS-G1 | ui-designer build-ready spec exists before presenter code (`docs/ui/UI_SPEC_sponsor_luauui.md`) | E5 spec artifact | **DELIVERED 2026-07-30** — 17 surfaces, 14 invariants, full state sets, verb×scheme matrix, 26 motion beats, 12 baseline criteria w/ file:line, 15-row doc-vs-shipped discrepancy table, 5 open UI-SPEC questions (packaged for the director in the review packet; build proceeds on the spec's recommendations, logged as provisional) |
| PS-G2 | ui-designer integrated review rounds over paired evidence until no automatable/specialist gap remains | E5 review artifacts + fix reruns | **ROUND 1 DONE 2026-07-30** (`reviews/round1.md`): 11 findings (2 BLOCKER: F1 detached/unclipped gate ring = solved-rect-space defect class, F1b faceless armed ghost; 6 MAJOR incl. F2 selection-overrides-recede; 3 MINOR) + 5 rulings (split-axis=sizeClass intentional diff; CoreGui list disable-while-presented — LuauUI side implementable, LEGACY side needs director approval; disconnected=keep w/ vocabulary conditions; Q1 confirmed, Q3 confirmed-amended-in-form; OWN-D13 CLOSED: flash+refill+toast is the revert w/ one-frame + visible-arrival conditions) + evidence gaps (post-L3 paired device captures owed, tablet pair state-mismatch). **ROUND 2 DONE 2026-07-31** (`reviews/round2.md`): round-1 re-tally 9 FIXED / 2 NV / 2 BROKEN and director DV 6 FIXED / 2 NV / 0 BROKEN, plus 12 new findings (2 BLOCKER N1/N2, 5 MAJOR, 5 MINOR) and 3 rulings — (a) ONE timer form: the 12-tick ring wins wherever a duration depletes, needle+hub is the zoned-scalar discriminator, and the reviewer WITHDRAWS the Q4 smooth arc; (b) the legacy objective pill goes to the director as ONE item and is flagged on screen meanwhile; (c) the restyled watched row recreated F4 and must carry a real plate LEVEL + a leading marker with the accent stroke reserved for focus/verdict. **FIX ROUND 3 DONE 2026-07-31** — every finding dispositioned in `responsibility-ledger.md`: both BLOCKERS, all 5 MAJORS and 3 MINORS closed with regressions; 3 framework rows added (OWN-D41 `fill` ZStack child pays its own margin, OWN-D42 orphaned focus-ring float, OWN-D43 recorded); 2 carried (N10 mark craft, N11 font weight = OWN-D43). **ROUND-3 VERIFICATION PENDING on the outstanding captures** — C1..C12 listed in `review-packet.md` §5.3, of which two are part-collected (`rows/C2-results-sponsor-rawpane-portrait.png` = sponsor/portrait only; `rows/C4-armed-ghost-own-slot.png` = restyled pose, ghost half NOT shown). Suites at close: game 2750 / LuauUI 2624, 11/11 checksums |
| PS-G3 | Fresh-context phase-gate verification of this ledger vs raw artifacts | independent review | OPEN |
| PS-G4 | Physical touch device, portrait+landscape | E4, D-phys | PENDING_PHYSICAL (by design until review packet) |
| PS-G5 | Physical gamepad / ten-foot | E4, D-phys | PENDING_PHYSICAL |
| PS-G6 | Weakest-supported-device run | E4, D-phys | PENDING_PHYSICAL |
| PS-G7 | Director FEEL + readability-at-race-speed approval | E5 | PENDING_HUMAN |

---

## Intentional differences log

Approved deviations from legacy, each with evidence and approval source.
(Empty at open.)

| ID | Difference | Why better/equal | Evidence | Approved by |
|---|---|---|---|---|
| PSD-1 | **A sponsor's results screen shows the final standings under the drama recap.** Legacy shows a sponsor no standings at all — `SponsorResults:960-999` is the drama branch and returns before the placement rows the racer branch builds (:1000-1090) | §S16's "2nd read: the standings / roll-call" has no content at all for a sponsor otherwise, which is the read the surface exists to give. The recap still LEADS (it is the sponsor's own reference content); the rows come from the SAME `RaceHudModel.rows` the racer's read uses, so the two roles cannot disagree about the order | `luauui_sponsor_results.spec` § "N2: the sponsor's StandingsBand carries the final order UNDER the recap" (both roles × both orientations); the defect it closes is round 2's N2 BLOCKER | **ui-designer review round 2 (2026-07-31), finding N2** — "the standings are the results surface's own content — and it is exactly where we beat the bar" |
| PSD-2 | **The chip row occupies a RESERVED top band; the platform-strip placement and its second-row reflow are not ported.** Legacy rides the physical top-bar row with a negative `GetGuiInset` offset (`SponsorGui`'s `layoutMap`) and falls to a second row when that band is narrow | The LuauUI HUD presents `rootPolicy = "coreSafeContent"`, so it cannot draw inside the platform strip at all — the reflow could only ever push the chips DOWN onto the map and the P1 row, which is what round 2 measured. The reserve is legacy's OWN number (`chipStripH`, `HudZoneModel:254-300`) applied on the below-the-strip rung, so the geometry matches legacy's narrow-portrait case exactly | `luauui_sponsor_table.spec` § "N3: the chip row NEVER paints over the table" (both orientations, every band and the top three rows); `luauui_sponsor_entry.spec` § "S2 with placeholder poses…" pins the 56 px band | ui-designer review round 2, finding N3 + spec amendment A8 |
| PSD-3 | **Ruling (a): the omen ring is the 12-tick segmented ring, not the smooth arc the spec ratified (§7 M25 / §11 D-3 / §12 Q4).** Ported from legacy's own gate-ring construction and shared with it | The reviewer WITHDREW the smooth-arc ruling on the pixels: a sponsor sees the gate ring and the omen ring within a second of each other on one play, and two forms for one clock is the split brain invariant 4 forbids; ticks also read as "three left" at billboard scale and at ten foot where an arc reads as an unlabelled fraction | `luauui_sponsor_omen.spec` § "RULING (a): wears the SAME 12-TICK ring…" (map) and § "the ring DEPLETES on the billboard" (world), both against the SAME `ringLit` the gate pill uses | ui-designer review round 2, ruling (a) — explicit withdrawal of Q4 |
| PSD-4 | **The legacy `ShowrunnerPillGui` objective pill is TAGGED on screen in the dev build** rather than suppressed for the LuauUI presenter | Suppressing it under LuauUI only would make the paired comparison dishonest and leave the objective unrendered; the tag names the legacy surface so nobody reviews it as the port's work. Presenter-side only — the frozen legacy module is untouched — and it retires when the director rules | `luauui_sponsor_presenter_lifecycle.spec` § "ruling (b): the legacy objective pill is FLAGGED on screen in the dev build" | ui-designer review round 2, ruling (b) step 2 (steps 1 and 3 remain the director's) |
| PSD-6 | **A `play`/`cooldown` gate pill wears the §1.2 FALLBACK badge (the author's initial on a neutral-rimmed chip), not a Roblox headshot.** Legacy fetches a thumbnail per identity and falls back to the same chip until it resolves | The fallback IS a complete badge by the avatar-badge spec's own rule ("a COMPLETE badge, never a bot glyph"), it is the form the director's own legacy style reference photographs ("author badge ('S' in a circle) attached at the LEFT cap"), and every geometry the badge occupies is legacy's to the pixel. A headshot pipeline is an engine seam this port deliberately does not hold (identity RESOLUTION stays outside the semantic model — see its header); adding one is additive and changes no layout | `luauui_sponsor_table.spec` § "DB-1: a PLAY slot wears the author badge at legacy's left cap; a LOCK wears none" (anatomy measured; the rim asserted neutral) | ui engineer, device round 1 — recorded for the director's next pass alongside the DB-1 device look |
| PSD-5 | **The results FIELD lists the FULL finishing order (whole grid, capped at `MatchTuning.gridMax`, your row plated), and RACE SPONSORS + the rivalry callout are their own regions beside the next-race actions and the ceremony rather than rows inside the roll-call list.** S16 v2 Q6 + Q8, built as recommended | Legacy reuses the LIVE HUD's ticker model for a results screen — top three plus your row — and its own `_standingsCap` comment (`SponsorResults:1039`) says the rest "stays in the scroll", a scroll the shipped band never gets. v2's field lane is that scroll: it is the one region slack flows to, so the whole grid fits with no layout change (the region is a list either way). Q8 puts the sponsor social proof beside the button it argues for and buys the seat list back its height | `luauui_sponsor_results.spec` — "Q6: the field lists the FULL finishing order…" (both roles, 1st…8th, your row plated), "Q6: the standings are the FULL finishing order, latched, capped at the grid" (pure, incl. the latched place and the tie-break) and "Q8: lanes by MEANING…" (rect-level: the callout shares the ceremony lane's x, RACE SPONSORS the actions') | director — S16 v2 §S16.14 flagged Q6/Q8 for the `UI-SPEC` gate; recommendation (a) built for judgement. **AMENDED twice by the director: DV5-1** moved RACE SPONSORS into the FIELD group (under the grid it names) so the trail lane is the two buttons alone, and **DV6-2** moved the promo BAIT/TEASE pair into the CEREMONY — they are the two strings DV5-1 named for the left column (`promo.bait.rival`, `promo.tease.streak`), which round 5 mis-read as the celebration's streak chip and the roll-call callout. Q8's own argument survives both moves |
