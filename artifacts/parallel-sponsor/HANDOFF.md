# Parallel LuauUI Sponsor Mode — bug-fix session handoff

Paste-able context for a fresh session. State as of 2026-08-01 END OF DAY
(after the desktop rounds A24–A43, the bug-fix + FTUE-economy session
A44–A45 + RED-TEAM fix round, and the FTU results ceremony v2 — all
evidence green, game suite 2973).

## What this is

RascalRally has TWO Sponsor Mode UIs. The shipped **legacy** one
(`games/RascalRally/code/src/client/Sponsor*.luau` + SocialBannerGui +
ShowrunnerPillGui) is **frozen** — 11 files checksum-locked, still the
production default, NEVER edit them. The new **LuauUI presenter** lives in
`games/RascalRally/code/src/client/LuauUISponsor/` and mounts only when the
workspace attribute `UseLuauUISponsor == true` at client startup
(`init.client.luau` ~line 730 branch). **The attribute is now SET TRUE and
LEFT IN THE PLACE (director instruction 2026-08-01 — supersedes the old
restore-to-nil rule for this one flag).** Rollback = clear the attribute.
Cutover/deletion are NOT authorized.

## Ground rules (binding)

- Legacy frozen: verify with `shasum -a 256 -c
  GameStudio/ui/LuauUI/artifacts/parallel-sponsor/baseline/legacy-checksums.txt`
  (run from `code/src/client/`; expect 11/11 OK). Sanctioned changed files
  are hashed in `baseline/sanctioned-changes-post-abc.txt`.
- Presenter code = declarative blueprints + `SemanticModel`/`Commands` only.
  NO Instance.new GUI, UserInputService, TweenService, platform names,
  engine selection, or per-height/-width branch logic (size-class facts come
  from `LuauUI.adaptive.conditions`). Reusable gaps get fixed in LuauUI
  (public API + tests + docs) then consumed — every such need is a row in
  `artifacts/parallel-sponsor/responsibility-ledger.md` (through OWN-D61).
- Visual identity anchors to LEGACY SOURCE CONSTANTS, cited — EXCEPT where a
  dated director ruling deliberately breaks parity (each such break is a
  numbered amendment in the UI spec; A24–A38 landed 2026-08-01). Director
  rulings live verbatim in
  `artifacts/parallel-sponsor/reviews/director-*-round-*.md` — read before
  re-litigating anything visual.
- Rows/racers carry NO rings, NO strokes, NO marker bars, NO slash marks,
  ever (director, repeatedly; the row stroke CHANNEL is deleted, A24/A32).
  Aim/drop/wind-up = plate wash only. Watched = plate level only. Focus ring
  never paints under touch. Blocked-while-held = the three-channel DIM
  (plate alpha + secondary text + desaturated swatch), nothing else.

## Build / verify

- Game suite: `cd games/RascalRally/code && ./run-tests.sh` → **2973 passed**.
  **NO file argument, ever** — an argument produces ~75 bogus failures.
  Before calling any red run a flake: check no sibling agent has a mutation
  applied (diff vs `.orig` backups) — the suite order is provably FIXED;
  a "flake" today was a concurrent mutation run (tasks/lessons.md).
- Framework: `cd GameStudio/ui/LuauUI && ./run-tests.sh` → **2755 passed**.
- Format: `stylua --check` both trees. Both suites + checksums must be green
  after every change; mutation-prove load-bearing new assertions.
- CLAUDE.md now carries a **LuauUI consumer lockstep** rule: any framework
  change updates game integration + a game-side test in the same task.

## What landed 2026-08-01 (the two desktop rounds) — where to look

- **Driving interference (flag on):** racer results present NON-sinking
  (`ResultsScreen.PRESENT_OPTS_RACER`, role-chosen in init.luau syncResults);
  `SponsorPose` context disabled unless sponsoring or results;
  **AssistPilot.luau reverse gate** (wall assist + chauffeur fire zero delta
  while velocity·look < −1 — they invert in reverse and pivoted karts 180°).
- **Camera reverse hitch (both modes):** `DrivingTuning.camera
  .reverseRotationFactor = 0.35` softens rotation chase only while backing
  up (`CameraController.luau` chase branch). Feel-locked domain: forward is
  byte-identical; the knob is the tuning surface.
- **Round reset (2nd sponsor round all-red):** PlayFlow per-slot
  presentation memos were owned by the item scope but cached for presenter
  lifetime — disposed at results unmount, frozen at `raceover`. Now owned by
  the play-flow scope (`PlayFlow.luau`; specs with `toRoundTwo` helper).
- **Drop visuals:** wind-up tell stroke deleted (was the "ring");
  `TablePlate` paints `hue("tablePanel")` (rows were darker than their
  backdrop); wash tints the row plate (`tellWash`); applied chip = sponsor
  **headshot** `rbxthumb` UI.Image + TickRing (no clock/padlock);
  `selectedKey` split from `watchedKey` + `onDeselect` on commit (row
  deselects after apply).
- **Minimized (follow) pose:** FTUE pull dots and the Race Drama dial are
  maximized-only (A26 = recorded legacy divergence for the dial).
- **Role modal:** legacy 240×52/42 box metrics + TextScaled arithmetic
  (`RolePickScreen.METRICS`/`textFit`, A27); sub-copy 19px × 2 lines at
  regular/wide (`subType`, A38); **both CTAs one shared neutral fill +
  3px `contentStrong` selection ring on the latched role** (A37 — reverses
  the old brightness-emphasis rulings; `Button.selected` dropped from
  results CTAs; same-fill/ring speced on BOTH surfaces).
- **Results:** Rally Points is a STANDING ceremony region when roomy
  (`opts.roomy = not compact/short`, A28) with legacy bar anatomy; rotation
  only when space is limited.
- **Table view:** 14px right inset at regular/wide (A29,
  `TableMetrics.listPadding`).
- **Countdown:** legacy 0.82-square plated numeral + stroke (A30).
- **Sponsor map:** start/finish tick + chevron via `Roster:startFinish()`
  world-space through the game projection (A31).
- **Cards/gates:** slash channel deleted (A32); gate legality no longer
  tick-blind — `SponsorStatusModel.liveGate`, rows flip live on expiry
  mid-hold (A33); card MARK desaturates whenever `cardsLive=false` (A34);
  FTUE dots gated on the same `cardsLive` fact (A35); drag-to-edge
  autoscroll was already wired — spec now pins real `scrollTop` movement
  (A36).

## What landed later on 2026-08-01 (rounds 3+ and the evening session)

- **Desktop round 3 + follow-up (A39–A43,** spec + memory have detail**):**
  `roomy` regained its `isShort` conjunct (landscape-phone reflow fix, plus
  a "NOTHING moves" schedule-end spec); gold COIN_COLOR restored; countdown
  tick extrapolation; map dots glide via per-dot springs; follow-label
  cycleWatch fix; A40 role modal widens at regular/wide; A41 intermission
  roll-call swap dropped; A42 CTAs bottom-center on both-axes-roomy; A43
  pre-race rival callout (`RollCallModel.gridCallout`, one framing home,
  now `CALLOUT_DWELL_S = 3.5` for BOTH consumers).
- **Finish-placement freeze:** racer's place could flip 1st→8th when the
  next round's grid re-seeded `pos` — `SemanticModel._resultsPlacement`
  freeze, order `placement or _finishedPlace[id] or r.pos`. Do NOT gate the
  `_resultsDirty` racing-edge rebuild (A43 reads results.rollCall there).
- **Round-boundary beat reset:** stale purple row = 4 leak paths
  (`RowBeats.resetAll()` + `StoryFlow:settleWash()` at the exit edge + tell
  reaping + `PlayFlow._round` epoch dropping stale airborne flights).
- **FTUE ECONOMY (the big one —** `docs/ui/FTUE_ECON_REVEAL_SPEC.md` **+ §9/§10):**
  First Smile ran `stepRoundLegacy` which NEVER settled — the first race
  paid 0/0. Now settles once per chair (`settleRound(karts, true)`
  firstBankOnly) gated by persisted `hasBankedFirstRace`/
  `hasBankedFirstSponsorRound`. RED-TEAM round found + fixed: the burn now
  happens AT the settle (standing DECISIONS rule: a persisted money gate
  never rides a transient presentation fact), flags store fails CLOSED
  (`tryGet`/degraded), burn keyed on `summary.role`, veterans migrate
  seeded-closed by ABSENCE-not-falseness (director ratified: stands).
  `EconPrimer` attribute = caption lifetime only.
- **FTU results ceremony v2 (director directive, supersedes v1 captions):**
  primed schedule = BIG "You earned N Chaos Coins!" (3.0s) → coin flight +
  count-up (2.5s) → BIG "You earned Rally Points!" + explanation (4.2s) →
  bar reveal (2.0s); floors derived at 0.3s/word; server window floor
  `MatchTuning.primerResultsTime = 16` via math.max off `signals.firstBanked`,
  `TailResultsS` published for mixed rounds; headline `fitWidthType` derives
  down from the slam 44px cap (German 26px); HeroBand yields during
  messages; RM = PrimedStatic; skip works from all four windows. Non-primed
  rounds byte-identical (spec-pinned).
- **Pre-show fix (GLOBAL, not FTU):** the coin chip painted `walletTo`+"+N"
  on frame one of EVERY positive round before the beat ran (`gainHeld`),
  and the roomy bar showed filled from t=0 (`barHeld`). Three old tests
  asserted the defect — rewritten.
- **Results CTA ring (director: "clicked sponsor, selection didn't change"):**
  ring = the PICK channel (`ResultsParts.ringRole`, optimistic), labels +
  content stay latched/server-confirmed (DB-6/DV5-2 intact; A37 sub-amendment).
  Sponsor direction confirms instantly server-side — that's why only it bug'd.
- **FTUE pull dots:** A44 = origin is the HELD card (pointer center while
  dragging, staging point while tap-armed; re-read every step, slot when
  docked); A45 = dots die PERMANENTLY on the first commit (drop on a racer);
  cancel/put-back does NOT kill; server-reject does NOT resurrect.
  `killPullLine` had zero callers before A45 — its comment lied.
- **Director ratifications (in DECISIONS.md):** veterans seeded closed
  STANDS; no land beat for a boundary-straddling accepted play = OK;
  once-only legacy-machine story moment = OK.
- **Standing rule (memory + specs):** all player-facing copy must survive
  German-class expansion — wrap/auto-fit + ~1.4x pseudo-loc spec with one
  unbreakable compound on the smallest size class.

## Live Studio verification recipe

1. `UseLuauUISponsor=true` is already set. For deterministic states also set
   `SponsorScenarioRig=true`, `TrackLayout="debug"` (restore THOSE TWO to
   nil/"firstSmile" after; the sponsor flag stays). Verify rojo synced
   (compare a changed file's Source; `rojo serve` runs from
   `games/RascalRally/code`).
2. Play Solo → Client VM: `ReplicatedStorage.SponsorCmd:FireServer("role","sponsor")`.
3. Deterministic states — Server VM, `workspace.RascalSponsorScenarioAPI`
   BindableFunctions: `select(name)` / `step(name)` / `holdPhase("racing"|
   "grace"|"results"|"prestart")` / `release()` / `report()`. **Invoke returns
   JSON STRINGS.** Scenarios incl. results-sponsor, celebration-burst, omens,
   legal-illegal-hand. Docs: `games/RascalRally/docs/luauui-sponsor-scenarios.md`.
4. Presenter state: `workspace.LuauUISponsorDevReport:Invoke()` → JSON
   (surfaces/focus/cards/watch/omen/story/results/composition + command
   counters + `list.scrollTop`).
5. Drive interactions: `workspace.LuauUISponsorDevDrive:Invoke(verb, arg)` —
   verbs tapCard/tapRow/beginDrag/dragTo/drop/cancel/skip/togglePose/watchDot;
   returns `{ok, consumedBy, counters}`. Routes through the REAL semantic
   entry points (downstream-action evidence; native routing still = device).
6. Captures to disk: `GameStudio/ui/LuauUI/tools/studio/capture_viewport.sh
   <out.png> 2 179 908 1044` (MCP screen_capture never writes files). Device
   shapes: StudioDeviceSimulatorService (`iphone_16`, `ipad_9th_generation`,
   `hd_1080`, `android_tv_1080`) — TV demotes wide→regular BY DESIGN.

## Instrument traps (all measured, don't rediscover)

- Device Emulator swallows ALL `user_mouse_input` injection; emulator off →
  instance-path clicks fire GuiButton.Activated only (no global streams; raw
  x/y dead) and clicks/Return DON'T reach buttons inside the virtual list's
  scroll host → use DevDrive for those flows. VirtualInput refuses ButtonB;
  ButtonY silently drops. Keyboard Return/Space deliver as GUI events on
  focused buttons outside scroll hosts.
- **`user_keyboard_input` NEVER reaches IAS** (measured: zero StateChanged
  events on `DriveInputs.brake` across injected holds) — you cannot drive the
  kart from injected keys. `InputAction:Fire()` on hardware Bool actions is
  an EDGE pulse — re-fire every RenderStepped to hold it; the `*Stick` touch
  actions are overwritten every frame by InputBridge's own flush.
- **Driving repro traps:** a Race Now pick MID-round gets an AI-paced kart
  until the next round composes (smooth 85 stud/s, ignores input); a first
  sponsor pick triggers the OBSERVER FTUE (`FtueSession=observer`) which also
  AI-drives your kart. Prove you're really the driver (grid start, fire
  throttle → speed responds) before trusting any input experiment.
- execute_luau can't reach module registries (isolated env) — that's WHY the
  Bindable surfaces exist. Renderer instance names are flat slash-paths; to
  click one by instance_path, temporarily rename it, SAVE the original name,
  restore after. Transient UI (results tail, omens 1-1.5s, pills) expires
  fast — hold via the rig or capture instantly.
- Headless drivers: use `adapter.touchTap` (real 3-part order), not the old
  one-call tap. Presenters in specs must inject ALL seams (engine touches
  behind `Seams`; the shared rig is `tests/lib/luauui_sponsor_rig.luau` —
  new parts/seams go THERE or 100+ specs break).

## The one big architecture fact for bug-fixing

The framework re-discovers input contributions via `presenter.refresh()`
(fix for the device tap-commit bug: wiring was once-at-present, and the
presenter constructs while the player is still a racer). If an interactive
element is dead: check it CONTRIBUTED (handleActivate/focus group) after its
region mounted. Results screen = `UI.Composition` declaration
(`ResultsScreen.luau`): ranked `UI.Region`s + span rows + empty-lane
collapse; debug via `debugReport().results` (arrangement/form/fallback) or
`LuauUI.composition.resolve` headless. ADR-0023.

## Open items (the likely next-session queue)

- **THE FTU FLOW NEEDS EYES (newest, highest value):** play a first race +
  first sponsor round end-to-end in Studio (dev reset:
  `SponsorFtue.handleFtueReset` now clears the banked pair too, so the loop
  works). Judge: 16s-to-CTA feel; the two BIG messages (do 3 headline lines
  read as one statement?); HeroBand yielding ~3s on the round you most want
  your place; compact celebration box growth on a landscape phone; whether
  a ~1.7% first bar-fill reads as a reward (known limitation, season
  thresholds are the real fix); primer lines in both A28 homes.
- **Device/desktop pass owed on the earlier 2026-08-01 fixes:** reverse no
  longer fights (real keyboard); camera reverse feel (`reverseRotationFactor`
  knob); drop wash + headshot arrival; countdown look + 3-2-1 on device;
  map dot glide; follow-label after cycling; tap-to-return on real input;
  bottom CTAs; widened role modal; gold coin chip; persistent Rally Points
  bar; CTA ring follows the pick now (re-check on device); dots-from-held-
  card + die-on-first-commit feel; dim-no-slash + live gate expiry; grey
  card marks; autoscroll feel on a real drag.
- **Flagged judgment calls for the director:** A33 client gate preview
  ≤0.25s more permissive than the server mirror (toast backstop); A37
  neutral CTA fill (punchier = one-line `ROLE_CTA_SURFACE` change); should
  the pull dots ALSO die after N seconds of clear hovering (current rule =
  first commit only)?
- **Device pass 2 legacy items** (packet §3.1): DB-4 tap-commit on real
  touch, DB-3b no focus ring under touch, DB-1 badge + DB-2 FTUE dots at
  device scale.
- **12 open decisions** (packet §4.2): UI-SPEC Q2/Q4/Q5, TUNE-Q1..Q5 (incl.
  M10 gate-slot pop not built — build record-driven; autoscroll chevron
  needs 2 framework halves), ShowrunnerPill legacy edit, PSD ratification,
  OWN-D43 font weight, N10 Headwind mark craft.
- **17 pending physical/human rows** with closing procedures: packet §6.
- Known accepted differences: PSD rows in `acceptance-ledger.md`.
- **NOTHING from 2026-08-01 is committed** (`games/RascalRally/code/.git`) —
  the whole day (A24 through the ceremony) is one uncommitted working tree.
  Director has not asked for a commit; ask before committing.

## Key docs

Master packet: `GameStudio/ui/LuauUI/artifacts/parallel-sponsor/review-packet.md`
(predates the 2026-08-01 rounds — the amendments A24–A38 in the UI spec are
the fresher truth for anything they touch).
Ledgers: `acceptance-ledger.md` (row truth), `responsibility-ledger.md`.
Build contract: `games/RascalRally/docs/ui/UI_SPEC_sponsor_luauui.md`
(S16 v2 = the approved finish screen; §11 D-1..D-15 discrepancy rulings;
amendments A24–A45 = the 2026-08-01 rounds, incl. A37 sub-amendment
ring=pick, A44 held-card dot origin, A45 die-on-first-commit).
FTU economy: `games/RascalRally/docs/ui/FTUE_ECON_REVEAL_SPEC.md` (§9 =
build notes + RED-TEAM fix round, §10 = ceremony v2 + criteria 21–25).
Decision log: `games/RascalRally/docs/DECISIONS.md` (2026-08-01 entries:
Q1–Q3, gate-persists-with-money standing rule, director ratifications).
Director rounds verbatim: `artifacts/parallel-sponsor/reviews/`.
Plan + boundary: `games/RascalRally/docs/LUAUUI_SPONSOR_PARALLEL.md`.
Lessons: `games/RascalRally/docs/lessons/` + repo-root `tasks/lessons.md`
(placeholder visuals never reach a sitting; identity channels anchor to
legacy constants; pre-sitting visual side-by-side pass is standing).
