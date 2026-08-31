[GATE-3]: APPROVE — all six loops complete and survive abuse; all five Round-1 findings re-verified FIXED at `6ba1907` with my own unchanged probes plus mutation tests proving both new checks bite; no regressions; full suite 7888 passed / 0 failed on the clean final sha. ONE OPEN ITEM, stated plainly rather than approximated: the Studio/live half was never possible — `examples/places/Facet-Showcase.rbxl` has still not been opened (only an empty `Place1` is connected, checked five times across two rounds), so every engine-side and physical-device claim for these six loops remains unproven and this approval covers the headless (`lune`) evidence class only.

# Fresh phase-gate review — "example-games-and-standalones"

Reviewer: fresh context, no implementer conclusions loaded. `artifacts/distribution-readiness/**`
conclusions were deliberately **not** read. Date: 2026-08-31.
Repository: `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`.

**Provenance, stated because HEAD moved under me.** The review began at `c552d66`
with `M examples/places/Facet-Showcase.rbxl` in the working tree. One commit
landed while I was driving — `02284b4` *"The showcase is stamped by what it is
built from, and rebuilds stop dirtying the tree"* — and the tree is now clean at
`02284b4`. That commit touches exactly three files: `.gitignore`,
`tools/build_places.sh`, and a rebuild of `examples/places/Facet-Showcase.rbxl`
(3891036 → 3891026 bytes). **No example source, no spec and no guide chapter
changed**, so every finding below holds against the current HEAD unaltered. It
does mean the `.rbxl` under test was rebuilt during this review and, per Half B,
still nobody has opened it.

Every loop below was **driven**, not inferred from a green suite. All driver
scripts were written into the session scratchpad (a symlink to the repo, so the
repo itself stayed read-only apart from this one file) and run under the pinned
`lune 0.10.4` from `~/.rokit/bin`.

---

## Summary of the six loops

| # | Loop | Happy path completed? | Proving observable | Abuse held? | Defects |
|---|---|---|---|---|---|
| 1 | Crossword tile game | ✅ | 6 turns played to `phase="lost"`, `score=27`, board `.AD.../.DEAR../.ON....` | ✅ 8 of 8 | 1 × low |
| 2 | Match-3 | ✅ | `swap → mark → remove:3 → gravity → refill:3 → land → idle`, `score=3 moves=1`; cascades of 3 and 4 `mark` phases played on the dealt board | ✅ 5 of 5 | none |
| 3 | Sensory-feedback demo | ✅ | opens `request=true`; all five fold nodes clear the fold on 4 device profiles × {0, LARGEST}; worst margin **−37 px** (slack) | ✅ 3 of 3 | 1 × low (copy) |
| 4 | Walk-up world terminal | ✅ | `idle → engaged → adjust → pending → confirmed → reset → exited`; gameplay `jump/move` counters frozen while engaged and moving again after exit | ✅ 6 of 6 | 1 × low |
| 5 | Sipworks | ✅ | `order(rejected) → order(confirmed) → stamps 9→10 → redeem → task="done" → reset` | ✅ 6 of 6 | none |
| 6 | Glade | ✅ | dew + **bramble** → `complete=true`, strip `2 of 2 ready`, toast "Emberwisp settles into Mossholm.", fly-in `v2` | ✅ 6 of 6 | none |

Cross-cutting: **the full deterministic suite passes** — `./run-tests.sh` → `7886 passed`,
zero `✗`, exit 0 (4 m 22 s wall, 22:54:22 → 22:58:44). That is context, not the
evidence for this gate.

---

## HALF A — headless, driving the real loops

### 1. Crossword tile game (`examples/gallery/examples/06_tile_game.luau`)

Driven through the **rendered nodes** (`adapter.tap` on `rackPath(slot)`,
`cellPath(r,c)`, `submitPath`, `undoPath`, `resetPath`) — not through the
example's own verbs, except where noted.

**Happy path.** Board is 7×7, centre `(4,4)`, rack `E,D,A,I,R,E,E`, seed
`20260829`, guaranteed opening `EAR`.

- Turn 1: `E@(4,3) A@(4,4) R@(4,5)`; the live verdict read `Making EAR — 3 points`
  **before** the press; submit → `score=3 turn=2`, three squares
  `committedAt` = `E/A/R`, rack refilled to 7 (`Q,D,D,I,O,E,E`), `cellState(4,4)`
  moved `centre → pending → committed`.
- Six turns played greedily to exhaustion: `EAR(3) → DEAR(5) → AD(3) → AD(6) →
  DEN(4) → ON(6)` = **27 points**, `phase="lost"`,
  hint `"Out of turns at 27 of 60 points. Press Start over to play again."`,
  progress `"0 turns left"`.
- Reset → `phase=playing score=0 turn=1 rack=7`, board empty, `lastError = nil`.
- `dispose()` clean.

**Abuse.** Every refusal named the exact problem and **changed nothing**:

| Attempt | Result |
|---|---|
| Submit with nothing placed | `"Place at least one tile before you submit."`; score/turn/rack unchanged |
| Tap a square with nothing held | `"Pick a letter from your rack first, then choose a square."` |
| Undo with nothing placed | `"Nothing to undo — you have not placed a tile this turn."` |
| Word that misses the star, then submit | `"Your first word has to cover the starred centre square."`; pending tiles **stayed put** (`pendingAt(1,1)="E"`), nothing committed |
| Second tile onto an occupied square | `"That square already has a letter."`; the held tile stayed held (`selected=2`) |
| Gap placement (`E@5,5 A@5,7`) | `"Leave no gaps — your tiles and the letters already on the board have to make one unbroken run."` |
| Disconnected word on turn 2 | `"After the first turn, a word has to touch a letter already on the board."`; turn/score unchanged |
| Tap/submit/undo after the end state | all inert; score, turn and rack all unchanged |

**Determinism.** Same seed + same script twice → byte-identical
`dump()`: `......./......./.AD..../.DEAR../.ON..../......./.......|rack=QIRIUEE|score=27|turn=7|phase=lost`.

**Defect TG-1 — off-board coordinates are accepted by the example's `place` verb.
Severity: LOW. Confidence: HIGH (measured).**
`activateCell(r, c)` (`06_tile_game.luau:828`) never calls `rules.onBoard(r, c)`.
Holding a rack tile and calling `game.place(9, 9)` removes the tile from the rack
and stores it at an off-board key. Measured: rack `7 → 6`, `pendingAt(9,9)="E"`,
`letterAt(9,9)=nil`, and the message line then reads
`"Place at least one tile before you submit."` — which is now false, a tile *was*
taken. It self-heals (the next successful submit clears the pending map and the
rack refills to 7; `undo` also recovers it) and `core:lastError()` stays `nil`.
*Not reachable by a player:* the board mounts only cells 1..7, `cellPath(9,9)`
resolves to no node, and the `examples` scenario exposes only `select`/`next`/
`theme` as steps — no coordinate step. Smallest corrective test: assert
`rackCount()` is unchanged after `select(1); place(0, 0)`.

### 2. Match-3 (`examples/gallery/examples/07_match3.luau`)

Driven by tapping two adjacent tiles (`cellPath`) and advancing the machine with
`presenter.tick(1/60)`. Positions read **board-relative** (`node.rect` and
`node.presentedPosition` minus `/Match3/Page/board`), and the mount's own 36
enter transitions settled first (90 frames) before any travel was read — without
that the swap records land on the tile's children and the root honestly reports
"no travel". My first two measurement attempts got this wrong; the numbers below
are the corrected ones.

**Happy path** (fixed board, swap `(3,3) ↔ (4,3)`):
`swap → mark → remove:3 → gravity → refill:3 → land → idle`,
`score=3 moves=1`, empty cells observed **during** the gravity phase, board full
at rest, tick hook released (`tickHookActive()=false`), `lastError=nil`.

**Cascades.** Played on the *dealt* (random) board with real legal moves:
play 2 produced a cascade with **3** `mark` phases, play 3 a cascade with **4**;
`score` reached 12 over 3 moves, board full, `hasLegalMove()=true`.

**Reduced Motion — results preserved, travel removed.** Same fixed board, same
swap, `reducedMotion` set through `tests/lib/world.luau`'s named option:

| | Full | Reduced |
|---|---|---|
| painted y through the 0.2 s swap phase | `117.1, 124.8, 132.7, 139.7, 145.7, 150.5, 154.4, 157.4, 159.8, 161.7, 163.1, 164.2` | `168.0 ×12` |
| distinct painted positions | **12** | **1** |
| frames strictly between the endpoints | **12** | **0** |
| `animationRecordCount()` peak | **13** | **0** |
| solved rect on the frame the swap call returns | 168 (the destination) | 168 |

Final board, `score`, `moves`, phase log and **tile ids** are byte-identical
across the two policies, and identical again on a repeat run.

**Abuse.** All held:
- Tapping two other tiles mid-cascade → `"The board is still settling — wait for the tiles to land."`; `score`/`moves` unchanged, phase log did not grow, outcome identical to the un-abused run.
- Public `swap()` mid-resolve → no-op (guarded on `resolving`).
- Non-adjacent tap → `"Tiles have to touch to swap. Pick a neighbour of the tile you chose."`, selection moves.
- Reset mid-cascade → `phase=idle`, `resolving=false`, tick hook dropped, `phaseLog` cleared, fresh full board; the 18 animation records visible at that instant are the **new** deal's enter transitions and settle to **0** after 3 s (verified separately).
- Artwork controls: `Fail a load → "Artwork: 1 failed, 4 ready"`; `Deliver` on a failed key correctly does nothing (a failed key has no pending request — the message already says to press Re-request first); `Re-request → "Artwork: loading 5 of 5"`; `Deliver → "Artwork: all 5 ready"`.

**No defects found.**

### 3. Sensory-feedback demo (`examples/gallery/scenarios/sensory_feedback.luau`)

**Opens with the request ON.** On a plain 390×844 mount, `steps.readHaptics()`
returns `state="undetermined"`, headline `"On · support unknown"`, detail
`"Roblox cannot tell whether this device has a motor."`, and the `PlayHaptics`
Toggle node reads `props.value = true`. Headless has no engine, so `undetermined`
with the request **staying on** is exactly the documented third state.

**Visible without scrolling — measured independently.** I re-measured rather
than re-running the spec's own case: for each of the four device profiles in
`tests/lib/device_views.VIEWS` at text offsets `{0, LARGEST}`, I compared each of
`Title`, `Intro`, `Haptics/PlayHaptics`, `Haptics/PlayState`, `Haptics/PlayNote`
against `adapter.windowRectOf("/SensoryFeedback/Page")`, with the **live** state
rather than a forced one:

```
compact-phone-portrait   359x718  text+0  fold=706   worst node −535
compact-phone-portrait   359x718  text+14 fold=706   worst node −200
compact-phone-landscape  705x338  fold=326           worst node −183 / −37
desktop-standard        1232x1067 fold=1055          worst node −912 / −766
console-ten-foot        1920x1078 fold=1006          worst node −739 / −655
```

0 problems; worst overrun **−37 px** (i.e. 37 px of slack) at
compact-phone-landscape + Largest text.

**Off / on / remount.**
- Press the sample control → history `release settle · Press sample → activate · built-in default` / `press contact · Press sample · built-in default`.
- Tap the toggle **off** mid-demo → `request=false`, `state="off"`, headline `"Off"`, bus subscribers `2 → 1` (the adapter unbound). A press while off records `(no request) · Press sample → activate · haptics off` and all four row readouts fall to `—`. Nothing pretends a sensation happened.
- Tap **on** again → `request=true`, `state="undetermined"`, subscribers back to 2, presses record real waveforms again.
- Dispose **while off**, then remount: opens `request=true` again, history reset to `"Nothing yet — press a control above."`, `requests=0`, subscribers back to 2.
- Third mount + dispose → subscribers **0**. No adapter leak across three mount/dispose cycles; `lastError=nil` throughout.
- Custom row on the third mount → `release swell · Custom sample · custom (this example's override)`, i.e. the override adapter answered and the installed one did not.

**Observation SF-1 — the static note reads oddly when the switch is off.
Severity: LOW (copy). Confidence: MEDIUM.**
`/SensoryFeedback/Page/Haptics/PlayNote` is the fixed caption
`"This demo turns haptics on for you."` (`sensory_feedback.luau:126`, rendered at
`:984`). It does not move when the player turns the switch off, so a player who
has just switched it off reads a sentence describing the demo's default under a
status line saying `Off`. It is defensible as a description of the demo's
decision rather than of current state, and the live status line directly above it
is correct — hence LOW and flagged as a judgement call, not a bug.

### 4. Walk-up world terminal (`examples/gallery/examples/outpost_terminal/`)

The engine half (the console part, the `ProximityPrompt`, the `SurfaceGui`) is
Studio evidence by construction and is **not** covered here — see Half B. What
*is* provable headlessly is the machine, the responder handoff, and the server's
judgement, and all three were driven.

**Happy path** (viewport = the terminal's own 640×480 canvas,
`presentationSpace="world"`), driven through the on-screen controls:
`idle` → `engage(START)` → `engaged` → three stepper `Inc`/`Dec` presses to
`d2/b1/w2` (readouts `2 / 1 / 2`; the consumer lines correctly read
`"The landing beacon is lit. (on Apply)"`) → tap **Apply** → `status=pending`,
envelope `kind=set alloc=d2/b1/w2` → server `rules.authorize` confirms →
`status=confirmed`, live state `d2/b1/w2`, message
`"All three are running, with 1 unit to spare."`, `complete=true` → tap **Reset**
→ pending → confirmed with a monotonic revision → live back to `d3/b0/w0`,
message `"The landing beacon is dark. The workshop is dark."` → tap **Exit** →
`phase=exited`, `exitReason="exit-control"`, `onExit` fired **exactly once**.

> Note on my own method: my first reset run appeared not to move the world. That
> was my harness reusing the fixed revision `99` (`ingest` correctly refuses a
> non-advancing revision), not a product defect. Re-run with monotonic revisions,
> reset moves the world. Recorded so the next reader does not repeat it.

**Gameplay input suppression and restoration** (a fake `CharacterContext` at
priority 1000 with `Jump`←Space/ButtonA and `Move`←Up/Down, per
`tests/responder.spec.luau`'s model):

```
mounted, nobody at the console   responder=passive  exclusive=false  jump=0 move=0
Space/Up before walk-up          responder=passive  exclusive=false  jump=1 move=1   ← gameplay reached
walk up (handle.engage)          responder=engaged  exclusive=true
Space/Up WHILE engaged           responder=engaged  exclusive=true   jump=1 move=1   ← gameplay frozen
   (and Space activated the focused Dec: draft door 3→2 — correct)
Down/Right/ButtonA               focus walks doorStep/Dec → beaconStep/Dec → beaconStep/Inc; draft d2/b1/w0
Cancel (ButtonB)                 responder=passive  exclusive=false
Space/Up after Cancel            responder=passive                   jump=2 move=2   ← gameplay restored
walk back up                     responder=engaged  exclusive=true
Exit control + host resign       responder=passive  phase=exited     onExit=1
Space/Up after exit              responder=passive                   jump=3 move=3   ← gameplay restored
```

The surface **survives** every exit (`/OutpostTerminal/Actions/Exit` still
mounted), so walking back up works — which is the documented
resign-not-dismiss contract.

**Abuse.**
- Walk away mid-flight (`exit("out-of-range")` while an apply is pending) → `phase=exited`, in-flight input cancelled, `onExit` once. A **late** server confirm arriving afterwards still ingests the world state (correct — the server really did apply it) and is invisible to the player; re-engaging clears the outcome and the next apply sends normally.
- Double exit → the second is idempotent (`already=true`, reason stays `"exit-control"`, `onExit` still fired once).
- `apply` / `reset` after exit → `sent=false, reason="exited"`. Re-engage → `sent=true`.
- Five server refusals, each with its own player sentence and no world movement: `holder` → *"Another engineer is at this console."*; `session` → *"This console session has ended. Use the terminal again to take control."*; `rate` → *"The terminal takes one command at a time. Wait a moment and try again."*; `distance` (999) and `distance` (unmeasurable) → *"You are 999 / inf studs from the console. Step within 10 to use it."*
- `setValue` clamps out-of-range input (`99 → 3`, `-5 → 0`); an unknown consumer is refused with *"The outpost has no consumer called 'reactor'."*
- Over-budget draft `3/2/4` → refused **locally** before sending: *"The generator makes 6 units and that allocation asks for 9."*, `refusedLocally=1`, `sent=0`.

**Defect OT-1 — `sendIntent` does not gate on "never engaged".
Severity: LOW. Confidence: HIGH (measured); severity confidence: MEDIUM.**
`sendIntent` (`outpost_terminal/init.luau:225`) refuses `phase == "exited"` and
`status == "pending"` and an invalid allocation, but not the `idle` phase.
Measured: on a freshly mounted terminal nobody has engaged,
`steps.apply()` returns `sent=true, requestId=3`, one envelope leaves, and
`status` becomes `pending` while `phase` stays `idle`.
Mitigations, all verified in this session: the on-screen Apply control is
`enabled = canApply` → `false` while idle, and a player tap on it sends nothing
(envelope count unchanged); the surface is a passive responder that sinks nothing
until engaged; and the **server** refuses an un-engaged sender —
`rules.authorize` step 1 returns `code="holder"`, *"Another engineer is at this
console."* So the trust boundary holds and this is a local-consistency gap, not
an authority hole. Smallest corrective test: assert
`steps.apply().sent == false` on a terminal that has never been engaged.

### 5. Sipworks (`examples/reference/p3_sipworks/`)

Driven through `adapter.driveActivate` on the real focus path
`…/Detail/Cta/Band/OrderCTA` (the exact closure the engine calls), with the
proof's own steps only where a headless run has no on-screen equivalent.

**Happy path** (shipped default seed = one stamp short of the card):

```
mounted        task=order    stamps=9   order=idle       mode=paid    away=1  canRedeem=false
open CTA blend  CTA label = "Place order — 49 Credits"
order #1        task=placing → task=rejected   attempts=1   stamps=9      ← the scripted rejection
order #2        task=placing → task=redeem     attempts=2   stamps=10     ← THE FINAL STAMP
                order=confirmed, ready=true, /OrderPlaced surface mounted (disc + Ready face)
done            order=idle, task=redeem, canRedeem=true, newSlots=1
stamps section  surfaces=[rewards,shell]; leaveStamps clears the new-slot badge
free pour       CTA label = "Redeem a free pour!";  order.mode=redeem
                task=done  redeemed=true  earned=11  spent=10  unspent=1  away=9
reset           task=order  stamps=9  order=idle  mode=paid  — the opening state exactly
```

The reset is player-reachable: `commands.serveAnother()` (the task band's own
"Serve another" button, `views/task.luau:250`) calls the same `resetToSeed()`.

**Abuse.** All held, `lastError=nil` throughout:
- Double-press the CTA while pending → the second press reaches the control and is ignored; `attempts` unchanged.
- Abandon mid-order: close the detail **and** move to another section while pending → the order still lands correctly; no orphaned state.
- **Reset mid-order** → immediately back to `task=order`, `order=idle`; 8 s later still clean (no late callback re-opens the abandoned order); the whole loop then replays to `task=redeem, stamps=10`.
- Order while payments are paused (the guard) → a `guard` surface is presented, `attempts` unchanged, `status` stays `idle`; after `guardOk` + `guard off` the order works.
- Redeem with an empty card → the CTA is still the paid verb, the order runs in `paid` mode, `spent` stays 0.
- `done` twice, `serveAnother` and `taskAction` out of turn → all idempotent or correctly restarting; no error.

**No defects found.**

### 6. Glade (`examples/reference/p1_glade/`)

Driven by tapping the real nodes (`/TaskBody/TaskOpen`, `/SupplyRow_dew`,
`/SupplyRow_nectar`, `/Act_<nectar>`), the way a finger would.

Seed `20260808`; task = **Mossholm**, for **Emberwisp**, which likes
**Bramble Nectar**. Opening state: `phase=start`, Mossholm has clover/full and
dew/low, strip `0 of 2 ready`.

**Happy path.**

```
open Mossholm      next line: "Open Mossholm and refill its dew."
tap SupplyRow_dew  phase=nectar  dewReady=true  strip "1 of 2 ready"
                   dew row "Done"; next: "Now set out Bramble Nectar in Mossholm."
                   toast refill:mossholm
tap SupplyRow_nectar → picker;  Act labels: starlight="Use 1"  bramble="Choose"  moonpetal="Shop"
tap Act_bramble    phase=done  complete=true  nectar bramble/full  strip "2 of 2 ready"
                   picker dismissed itself; toast "task" = "Emberwisp settles into Mossholm."
                   fly-in v2 recorded;  visits.current(mossholm) = emberwisp
```

**Reset (Fresh Start).** `freshStart` raises the confirmation surface;
`confirmFreshStart` returns everything to the seeded opening (`phase=start`,
clover/full, dew/low, section `glades`); the whole loop then replays to
`complete=true` a second time. `lastError=nil`.

**Abuse.**
- **The wrong nectar** (clover instead of bramble): nothing advances — `phase` stays `start`, both task rows stay `"To do"`, strip stays `0 of 2 ready`, the next line is unchanged. The refusal is by absence, which is the right shape here. (Choosing clover *does* refill the nectar supply — "assigns and refills in one act" — which is correct and does not tick the task row.)
- A **premium** nectar with an empty satchel → opens the **shop** instead of using one (`surfaces=[picker,shop]`), the nectar does not change, the satchel stays 0.
- Refilling dew that is already full → level unchanged (`1 → 1`), no double-credit.
- The **drain un-ticks a ready row**: advancing past `DRAIN.dew.low`/`.empty` moves the phase to `resume` with *"Mossholm's supplies have run down again. Refill the dew and set out Bramble Nectar."* and strip `0 of 2 ready` — the task does not become silently unsatisfiable, and refilling recovers it to `done`.
- After completion the drain does **not** un-complete: `complete` stays latched `true` even with both supplies empty, and feeding it the wrong nectar afterwards changes the nectar without disturbing the completion.
- Cancelling the Fresh Start confirmation (`dismissTop`) preserves progress (`dewReady` still true).
- `prepareAgain` after completion returns to the opening state.

**No defects found.**

---

## Cross-cutting defect

**DOC-1 — `docs/guide/04-tutorial-examples.md` §4.7 (Match-3) contradicts the
shipped example on four mechanism claims.
Severity: MEDIUM. Confidence: HIGH (each claim checked against the source and
against a live drive).**

This chapter is named in this gate's own list of sources of truth, so a reviewer
or a consumer reading it is being told the wrong thing about the loop this stage
shipped.

| Doc §4.7 says | The shipped example does |
|---|---|
| *"One thing the example is explicit about **not** doing: sliding a tile smoothly from one cell to another. That would animate a layout position over time, and time-based layout animation is a future expansion of the library. So tiles change instantly here."* (lines 1118–1121) | Tiles **do** slide. `07_match3.luau` has four `pres.withAnimation(TILE_MOTION, …)` call sites (`:663, :673, :713, :760`), a seven-phase clock-driven machine, and a full Reduced-Motion parity story. I measured **12 distinct intermediate painted positions**, all strictly between the endpoints, over the 0.2 s swap phase. |
| *"The tile is now one theme metric, on a `UI.Grid`:"* + the snippet `UI.Grid({ id = "board", columns = COLS, itemSizing = "uniform", gap = "xs", children = cells })` | The board is `UI.Anchor({ id = "board", overflow = "clip", … })` wrapping a keyed `UI.ForEach({ id = "tiles", … })` (`:570–592`). No `UI.Grid` with `id = "board"` exists in the file; the only `UI.Grid` is the artwork row (`:963`). |
| *"the board rows are `HStack`s. So the presenter derives the grid navigation from the layout automatically, and a gamepad moves around the board with no custom context"* | There are no per-row `HStack`s. The source's own comment at `:996` states the opposite: *"a `UI.Anchor` has no rows to read … so an anchored board is one of the 'hand-wired screens' `navigationGroups` exists for."* |
| *"this example, too, passes no `present()` opts"* | `local handle = pres.present(screen, { navigationGroups = navigationGroups })` (`:1050`). |

The chapter never mentions `withAnimation`, the phase machine, the cascade
ordering, or Reduced Motion at all — the only two hits for "animat" in the whole
file are the two lines that say it does not happen.

**Not caught by any gate producer.** `tests/example_drift.spec.luau` is a
*property-authority* lint (it bans literals that bypass theme authority); it does
not compare prose to source. `tools/lune/check_docs.luau` covers the theme
surface, the guide index, link resolution and the scenario steps the guide
teaches — not §4.7's mechanism prose. Smallest corrective test: extend
`check_docs` with a grep anchor asserting §4.7 names `withAnimation` and does not
contain "tiles change instantly".

For contrast, §4.6 (Crossword) was checked the same way and is **accurate**:
`pres.present(screen)` really does pass no opts (`06_tile_game.luau:1239`), and
"nine refusals and nine sentences" matches exactly the nine `refuse("…")` codes
`rules.validate` can emit (`empty, occupied, axis, gap, centre, connect, long,
unknownCrossing, unknown`) — `nothingHeld`/`nothingPlaced` are correctly excluded
by the source's own comment as non-rule refusals. I initially suspected a
miscount here and it is not one.

---

## Environment finding

**ENV-1 — a stale `studio_sync` on :8642 answers `/manifest` with HTTP 500.
Severity: LOW (dev tooling). Confidence: HIGH on the observation, MEDIUM on the
cause.**
`lune run tools/lune/studio_sync`, PID 28284, started **2026-08-30 09:22** (~25 h
before this review), is still LISTENing on 127.0.0.1:8642 and returns:

```
/          -> 404
/manifest  -> 500   ("Lune: Internal server error")
```

A freshly-computed manifest succeeds — `studio_tree.entries("gallery")` returns
**364** entries from the current tree. `studio_sync.luau` enumerates the tree
**once at startup** (`local entries = studio_tree.entries(mode)`) but stats those
files per request to recompute the stamp, so a file deleted or renamed while the
server runs poisons `/manifest` for the rest of the process's life. That fits the
`ref_wardrobe` deletion recorded in `examples/gallery/scenarios/init.luau` as
happening on 2026-08-30. Practical consequence: any `tools/studio/inject.luau`
run attempted right now fails at its first `HttpService:GetAsync`, and the
injector's only diagnostic is a raw HTTP error. Fix: restart the server; harden
by re-enumerating per request, or by refusing to serve when a startup-time entry
has vanished.

---

## HALF B — Studio, live: **NOT PERFORMED**

**`examples/places/Facet-Showcase.rbxl` is not open in the connected Studio.**
Stated plainly rather than approximated, per this review's instructions. The
evidence, gathered at three separate points during the review (start, middle,
end — the last after the full ~13-minute suite run):

- `list_roblox_studios` → exactly one instance, `be177366-90aa-48ad-b2f4-8b57f3140516`, named **`Place1`**.
- `get_studio_state` → `Edit` mode only; no `Client`/`Server` datamodel.
- `execute_luau` (Edit) on that instance:
  - `game.PlaceId = 0`, `game.Name = "Place1"`
  - `ReplicatedStorage` children: **(empty)** — no `Facet`, `FacetExamples`, `FacetScenarios`, `FacetThemes`
  - `Workspace` children: `Camera`, `Baseplate`, `Terrain`, `SpawnLocation` — no console part, no `FacetShowcaseAPI`
  - `workspace:GetAttribute("Facet_Scenario")` = `nil`; `Facet_ThemePackage` = `nil`
  - `StarterPlayer.StarterPlayerScripts` children: **(empty)** — no `Gallery` bootstrap
  - `ServerScriptService` children: **(empty)**
- `search_game_tree` (Edit, depth 6, keywords `Facet, Showcase, Scenario, Gallery`) → **"No instances found."**

So the drive surface this half needs — `workspace.FacetShowcaseAPI`
(`list`/`current`/`showNext` BindableFunctions, `docs/guide/11-device-verification.md`
§"The hands-on place") and `_G.FacetScenario` (`report`/`step`/`reset`/`list`,
`examples/gallery/scenarios/init.luau` header) — does not exist in the connected
session. `start_stop_play` was **not** called: entering Play on an unrelated empty
baseplate would disturb the user's session and would produce no evidence about
this gate.

I also considered and **rejected** injecting the framework into the open place
with `tools/lune/studio_sync` + `tools/studio/inject.luau`. Two reasons: the
place under test is a specific built `.rbxl` and `Place1` is not it, so the
result would not be evidence about the artifact this gate covers; and the
injector's only source server is the stale one described in ENV-1, which
currently returns 500 — a Studio session driven through it would at best run
yesterday's tree while reporting success, which is precisely the false-evidence
shape `inject.luau`'s own header warns about.

**Consequence for the gate.** Everything below stays unproven for this stage
until someone opens `examples/places/Facet-Showcase.rbxl` (or the four
`Facet-Ref-*.rbxl` places) and drives it:

- the terminal's **engine half**: the console `Part`, the `SurfaceGui`, the walk-up `ProximityPrompt`, the second host, the real responder handoff, and the eight exit paths that originate on the host side;
- that each loop actually **mounts and paints** through the real adapter — the crossword's 49 plates, the match-3 board's 36 tile images, Sipworks' and Glade's shells — as opposed to solving correctly against `fake_target`;
- real pointer/touch/gamepad delivery into these six loops;
- the demo chip and theme chip actually reaching `ex06`, `ex07` and `sensory-feedback`;
- frame work, paint cost, and anything a `.rbxl` build could have baked stale — `examples/places/Facet-Showcase.rbxl` was **rebuilt during this review** (commit `02284b4`) and nothing here reads it.

For the record, reachability of the six loops from the shipped entry points was
checked **statically**: `demo_picker.DEMOS` carries `ex06`, `ex07` and
`sensory-feedback`; `scenarios/init.luau` `ORDER` carries `ref_glade`,
`ref_sipworks` and `outpost_terminal`; and `examples/places/` holds
`06_tile_game.rbxl`, `07_match3.rbxl`, `Facet-Ref-Glade.rbxl`,
`Facet-Ref-Sipworks.rbxl` and `Facet-Showcase.rbxl`. The outpost terminal is
deliberately absent from the picker (documented in `init.luau`: a fixture needing
an engine fixture cannot be mounted by the chip strip).

---

## What this review does NOT cover

By `docs/guide/11-device-verification.md`'s five evidence classes, **everything
above is the `lune` (headless) class** — the weakest of the five, and the guide
says so itself: *"a fast headless number is not a phone result, and no amount of
it ever becomes one."*

| Class | Covered here |
|---|---|
| `lune` (headless) | ✅ all six loops, happy path + abuse + determinism |
| `studio-emulated` | ❌ not performed (Half B above) |
| `desktop-retail` | ❌ |
| `phone-physical` | ❌ |
| `console-physical` | ❌ |

Specifically out of scope, per the guide's own "What the automated matrix can
never close": physical touch targeting, gestures and touch feel; real gamepad
delivery, platform arbitration and console behaviour; the mobile OS keyboard; OS
display scaling; retail-client networking; low-end CPU/GPU/memory/thermal/battery
or frame-time performance; and subjective readability, hierarchy, motion or
production feel. Also not covered by me: theme-package sweeps (I drove Studio
Neutral only, except where the scenario mount set its own metrics), pseudo-locale
expansion, and any claim about the built `.rbxl` artifacts.

---

# ROUND 2 — re-verification of the five findings, 2026-08-31

Requested by the coordinator: re-verify all five findings, then complete Half B.
Everything below is my own instrument output, not the fix author's account.

## The tree moved three times during this round — pinned state

| When | HEAD | What |
|---|---|---|
| Round 1 end | `02284b4` | clean |
| Round 2 start | `02284b4` + 5 modified files | the fixes, uncommitted |
| mid-round | `6a9e5f8` | fixes committed — **and this tip was red** (see below) |
| **final, verified** | **`6ba1907`**, clean tree | the same commit message, amended |

The five product files I verified are **byte-identical** across `6a9e5f8` and
`6ba1907` (md5: `4b519fda…` guide, `4ca3e73e…` `06_tile_game`, `89b3ac6e…`
`07_match3`, `5edf2950…` `outpost_terminal/init`, `66f999ba…`
`sensory_feedback`), so every behavioural result below stands against the final
sha. Only `tests/outpost_terminal.spec.luau` moved between the two.

**Process observation (not a product defect).** The first fix commit `6a9e5f8`
shipped its new outpost case calling `f.w.dispose()` — a method
`tests/lib/world.luau` does not define (the file's other 19 disposals all call
`f.built.dispose()`). My full-suite run against that tip returned
**`1 failed, 7887 passed`, exit 1**:

```
outpost terminal: engage -> adjust -> apply -> success -> reset -> exit
  ✗ a terminal nobody engaged sends nothing, even to a scripted apply
      tests/outpost_terminal.spec:419: attempt to call a nil value
```

It was amended to `6ba1907` while I was verifying. Worth recording only because
a single-spec run hid it — `lune run tests/run_one outpost_terminal` reported
`41 passed` against a tree whose suite was red, because I ran it before the
broken line landed. The gate's evidence has to be a **full suite on the final
sha**, which is what the figure below is. (My own harness masked this once too:
`./run-tests.sh > log; echo EXIT=$?` makes the *echo* the backgrounded command's
exit status, so the task notification said "exit code 0" while the run had
exited 1. Read the transcript, not the wrapper.)

## Finding-by-finding

### DOC-1 (medium) — **FIXED.** Re-ran all four of my original checks by reading.

| My round-1 check | §4.7 now says | Verdict |
|---|---|---|
| "tiles change instantly here" | *"Tiles travel. A swap, a fall and a refill each move through `presenter.withAnimation`, driven by a small phase machine (swap, mark, remove, gravity, refill, land, idle) … With Reduced Motion on, the travel is skipped and the result is identical: the same board, score and tiles, painted in place."* | ✅ and it matches what I measured — 12 distinct intermediate positions Full vs 1 Reduced, 0 animation records, identical board/score/moves/ids |
| `UI.Grid({ id = "board", columns = COLS, … })` | `UI.Anchor({ id = "board", children = { UI.ForEach({ ... }) } })` | ✅ matches `07_match3.luau:570` |
| "the board rows are `HStack`s … derives the grid navigation from the layout" | *"Because the board anchors tiles freely, no layout rows exist for the presenter to derive navigation from."* | ✅ matches the source's own comment at `:996` |
| "passes no `present()` opts" | *"this example declares its own groups and passes them as `present()` opts (`navigationGroups`): the board is one rectangle group, and a gamepad crosses it left, right, up and down."* | ✅ matches `:1050`, and the left/right-lane / up-down-line description matches `navigationGroups()` |

The rewrite also fixed a **fifth** drift I had not flagged: the `CELL` snippet's
metric path went `controls.large.height` → `controlSizes.large.height`, which is
what `07_match3.luau:72` actually declares. Confirmed the old spelling appears
nowhere in the example. §4.6 (Crossword) was not touched by the diff and remains
accurate.

*Informational, not a defect:* the doc's phase list omits `revert`, the eighth
entry in `PHASE_SECONDS` and the phase a player hits on every non-matching swap
("That swap makes no run of three."). The sentence is framed as "a small phase
machine (…)" rather than an exhaustive list, so it is not a false claim — but a
reader who tries a bad swap first meets a phase the chapter never named.

### TG-1 (low) — **FIXED**, and the new check **bites**.

The guard is at `06_tile_game.luau:832`, before `rules.key`, silent and
commented. Verified three ways:

1. **My round-1 probe, unchanged, re-run** (`d4_tile_offboard`) — the differential oracle:
   | | Round 1 | Round 2 |
   |---|---|---|
   | rack after `select(1); place(9,9)` | **7 → 6** | **7 → 7** |
   | `pendingAt(9,9)` | `"E"` | `nil` |
   | tile still held | no | yes |
2. **The new spec case exists** — `tests/example_tile_game.spec.luau:553`, *"8b — an off-board square takes nothing, so a stray call cannot beach a tile"*; it holds the tile and then proves a real square still accepts it. `lune run tests/run_one example_tile_game` → **50 passed**.
3. **Mutation test.** I copied the example into the scratchpad with exactly the 5-line guard removed (verified: 5 lines gone, the other 4 legitimate `rules.onBoard` uses kept) and re-ran the probe: `selected()=nil`, rack `7→6`, `pendingAt(9,9)="E"` — the round-1 defect returns, so case 8b **would fail**. The check is not decoration.

### OT-1 (low) — **FIXED**, and the new check **bites**.

`sendIntent` now refuses `phase == "idle"` with `reason = "idle"`
(`outpost_terminal/init.luau:229`), commented.

1. **My round-1 probe, unchanged** (`t3`): idle apply was `sent=true, requestId=3, envelopes=1`; it is now `sent=false, requestId=nil, envelopes=0`, and `status` stays `idle` instead of going spuriously `pending`. The script then *crashed* at its next line indexing `.payload` on a nil envelope — the oracle firing exactly as it should against a fixed tree.
2. **The committed spec case exists** — `tests/outpost_terminal.spec.luau:412`. I initially reported it missing; that was **my error** (`git status` had not yet shown the file and my grep pattern missed it). Correcting the record: it exists, and my round-1 report's claim that it did not is withdrawn.
3. **Mutation test.** Guard removed (6 lines), probe re-run: idle apply → `#sent=1`. The case **would fail**. Not decoration.
4. I also checked whether the one uncommitted line I saw mid-round (`f.steps.setValue("door", 2)`) was propping up a failing assertion. It is not: I drove the case's exact sequence both with and without it and `#sent` is 1 either way — an unchanged draft still sends. Cosmetic strengthening only.

### SF-1 (low) — **FIXED.**

`playNote` is now `"This demo asks for haptics when it opens."`
(`sensory_feedback.luau:126`). Re-ran my round-1 `s2` probe and read the rendered
`/SensoryFeedback/Page/Haptics/PlayNote` node in **all six** states it passes
through — first open, after switching off, after switching on, off-before-dispose,
on reopen, and third mount — and it is that one sentence every time. True in
every state, which is what the finding asked for. `control_feedback` → 72 passed,
`sensory_feedback` → 14 passed.

### ENV-1 (low) — **FIXED.**

`lsof -nP -iTCP:8642 -sTCP:LISTEN` returns nothing; the port is free. The stale
`lune run tools/lune/studio_sync` (PID 28284, started 2026-08-30 09:22) is gone.
Re-checked twice, including after the suite run.

## No regressions — all six loops re-driven

Every round-1 driver re-run unchanged against `6ba1907`. Results identical:

| Loop | Round-2 observable |
|---|---|
| Crossword | 6 turns to `phase="lost"`, score 27; post-end taps inert; reset clean; dispose clean |
| Match-3 | Full 12 distinct painted positions / peak 13 animation records; Reduced 1 position / **0** records; board, score, moves, phase log and tile ids identical; cascades of 3 and 4 `mark` phases on the dealt board; reset mid-cascade drops the tick hook |
| Sensory | opens ON; off/on; three mount/dispose cycles return bus subscribers to 0 |
| Terminal | engage → adjust → apply → confirm → reset → exit, `onExit` once; gameplay `jump/move` frozen while engaged (2→2) and moving again after exit (→3) |
| Sipworks | paid order → 10th stamp → free pour → `task=done` → reset to the opening state |
| Glade | dew + bramble → `complete=true`, "Emberwisp settles into Mossholm."; wrong nectar advances nothing; Fresh Start restores |

Determinism re-confirmed: crossword `dump()` byte-identical across two runs;
match-3 board/log/score/ids identical across two Full runs **and** between Full
and Reduced.

**Full suite on the final sha `6ba1907`, clean tree: `7888 passed`, zero `✗`, exit 0.**
(Re-checked after the run: still `6ba1907`, still clean, the four product files still at the same
md5s — so the green belongs to the tree I verified.)

## HALF B — still NOT PERFORMED

Checked again at the start of this round and again after finishing the
re-verification, per the brief's "one check now, one more after your
re-verification". Both times, and a third `get_studio_state` in between:

- `list_roblox_studios` → one instance, `be177366-…`, named **`Place1`**; `get_studio_state` → `Edit` only, no Client/Server datamodel.
- `execute_luau` (Edit) on it: `PlaceId=0`, `Name="Place1"`, `ReplicatedStorage children: (none)`, `Workspace: Camera, Baseplate, Terrain, SpawnLocation`, `workspace.FacetShowcaseAPI = nil`, `Facet_Showcase = nil`, `Facet_Scenario = nil`, `Facet_SourceStamp = nil`, `StarterPlayerScripts: (none)`.

`examples/places/Facet-Showcase.rbxl` has still not been opened. **This remains
the one open item on the gate**, and its coverage gap is unchanged from Round 1:
the terminal's engine half (console part, `ProximityPrompt`, `SurfaceGui`, the
host-side exits), that each loop actually paints through the real adapter, real
pointer/touch/gamepad delivery, the demo and theme chips, and every physical
evidence class. Note ENV-1's fix removes the blocker that would also have
stopped a `tools/studio/inject.luau` route, so the live half is now purely
waiting on the place being opened.

## Round 2 commands

```bash
# affected specs, individually
lune run tests/run_one example_tile_game        # 50 passed
lune run tests/run_one outpost_terminal         # 42 passed (final sha)
lune run tests/run_one control_feedback         # 72 passed
lune run tests/run_one sensory_feedback         # 14 passed
lune run tests/run_one examples_games           # 39 passed
lune run tests/run_one example_match3_motion    # 21 passed
./run-tests.sh                                  # full suite on 6ba1907

# my UNCHANGED round-1 drivers, as differential oracles
lune run d4_tile_offboard      # TG-1: rack 7->7, pendingAt(9,9)=nil  (was 7->6, "E")
lune run t3                    # OT-1: idle apply sent=false, envelopes=0 (was sent=true, 1)
lune run s2                    # SF-1: the note in all six states
lune run d6_tile_end / m6 / p2 / g3 / t4 / det   # all six loops + determinism, no regression

# new in round 2
lune run ot_probe              # the committed outpost case with and without the uncommitted line
lune run mut_probe             # mutation test: both guards removed -> both new checks FAIL
perl -0777 -pe 's/…onBoard guard…//'  06_tile_game.luau  > mut/06_tile_game.luau
perl/sed  '…idle guard…'              outpost/init.luau  > mut/outpost_terminal/init.luau

# provenance and environment
git log --oneline; git status --porcelain; git diff HEAD --stat
md5 -q <the five product files>          # identical across 6a9e5f8 and 6ba1907
lsof -nP -iTCP:8642 -sTCP:LISTEN         # empty — ENV-1 fixed
```

Roblox Studio MCP calls this round (all read-only, no `start_stop_play`):
`list_roblox_studios` ×3, `get_studio_state` ×1, `execute_luau(Edit)` ×1 — all
reporting the empty `Place1` above.

Repository writes by this review, both rounds: **this file only.** No commits, no pushes.

---

## Exact commands and calls run

Environment for every shell call: `export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"`.
`SP` = the session scratchpad; `$SP/facet` is a symlink to the repository, which
is how the drivers `require` library and example modules without writing into the
repo.

```bash
# suite (context, not this gate's evidence)
./run-tests.sh                       # -> "7886 passed", 0 x ✗, exit 0
lune run tests/run_one example_match3_motion    # -> 21 passed (read for its measurement idiom)

# scratchpad drivers (each written with Write/heredoc, then run from $SP)
lune run d1_tile              # crossword: initial deal, opening word, node presence
lune run d2_tile              # crossword: 8 abuse attempts (wrong board size, corrected below)
lune run d3_tile              # crossword: correct 7x7 geometry, happy turn 1+2, abuse A-D
lune run d4_tile_offboard     # crossword: TG-1, place(9,9) off-board probe
lune run d6_tile_end          # crossword: full 6-turn game to phase="lost", post-end inertness, reset, dispose
lune run m1 / m2 / m3 / m4 / m5     # match-3: iterative measurement (m2-m4 were my wrong measurements)
lune run m6                   # match-3: settled-mount travel, Full/Reduced parity, real cascades, reset abuse
lune run m7                   # match-3: artwork controls, animation-record settle after reset
lune run s1                   # sensory: opens ON, independent fold measurement, press/release/select/custom
lune run s2                   # sensory: toggle off/on mid-demo, three mount/dispose cycles, bus-subscriber census
lune run t1 / t2 / t3 / t4    # terminal: idle/engage probe, full loop + 6 abuse groups, responder + OT-1,
                              #           gameplay-input suppression and restoration
lune run p1 / p2 / p3         # Sipworks: opening state, full paid->stamp->free-pour->reset loop, 6 abuse groups
lune run g1 / g2 / g3 / g4    # Glade: opening state, picker probe, wrong-nectar + happy path + Fresh Start,
                              #        6 abuse groups
lune run det                  # determinism replays for the crossword and match-3
lune run $SP/sync_probe       # ENV-1: studio_tree.entries("gallery") -> 364 entries from a fresh process

# environment
lsof -nP -iTCP:8642 -sTCP:LISTEN          # -> lune PID 28284, started Sun Aug 30 09:22:27 2026
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8642/manifest   # -> 500
ps -o pid,lstart,command -p 28284
```

Roblox Studio MCP calls (all read-only; no `start_stop_play`, no writes):

```
list_roblox_studios                       x3   -> [{ id: be177366-…, name: "Place1" }]
get_studio_state(be177366-…)              x2   -> Edit only
execute_luau(be177366-…, Edit)             x1   -> PlaceId 0 / Name "Place1"; empty ReplicatedStorage,
                                                  StarterPlayerScripts and ServerScriptService;
                                                  Workspace = Camera, Baseplate, Terrain, SpawnLocation;
                                                  Facet_Scenario = nil, Facet_ThemePackage = nil
search_game_tree(be177366-…, Edit,
    keywords "Facet, Showcase, Scenario, Gallery", depth 6)  -> No instances found
```

Sources read (not modified): `docs/guide/04-tutorial-examples.md`,
`docs/guide/11-device-verification.md`, `examples/gallery/examples/06_tile_game.luau`,
`07_match3.luau`, `outpost_terminal/{init,rules}.luau`,
`examples/gallery/scenarios/{init,sensory_feedback,outpost_terminal}.luau`,
`examples/gallery/client/demo_picker.luau`, `examples/reference/p1_glade/init.luau`,
`examples/reference/p3_sipworks/init.luau` (+ `services/task.luau`),
`examples/showcase.project.json`, `tools/lune/{studio_sync,check_docs}.luau`,
`tools/studio/inject.luau`, `tests/lib/{world,fake_target}.luau`,
`tests/{examples_games,example_match3_motion,example_drift,control_feedback,sensory_feedback,outpost_terminal,responder}.spec.luau`,
`tests/reference/{glade,sipworks}_spec.luau`.

Repository writes made by this review: **this file only.** No commits, no pushes.
