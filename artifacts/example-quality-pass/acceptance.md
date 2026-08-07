# Tutorial gallery quality pass — acceptance ledger (roadmap Step 10)

**Stage:** `example-quality-pass` (docs/plans/example-quality-pass.md)
**Written:** 2026-08-06, BEFORE implementation (execution contract §2).
**Gate:** `tools/gate.sh example-quality-pass` → `artifacts/example-quality-pass/gate.json`

Status vocabulary (contract §2): `PASS_AUTOMATED`, `PASS_PHYSICAL`, `PASS_HUMAN`,
`FAIL_PRODUCT`, `FAIL_ENVIRONMENT`, `PENDING_PHYSICAL`, `PENDING_HUMAN`. A row cannot
pass through a different, easier row. In particular: **a source read never closes a
gameplay row**, **a direct call to a game method never closes a native-input row**, and
**the device emulator never closes a physical touch or gamepad row**.

Every row below starts `PENDING`. It flips only when a tool result in the closing run
observed the behavior and the named artifact exists.

## Baseline facts this ledger is written against (audited 2026-08-06, current source)

Measured, not assumed — each was read out of the files named.

- **Seven example modules** live in `examples/gallery/examples/`
  (`01_temperature_converter` 159 lines … `07_match3` 322 lines) plus `assets.luau`.
  They are engine-free: they build blueprints against the `(LuauUI, core, deps)` the
  gallery bootstrap hands them.
- **The mount path is `examples/gallery/client/init.client.luau` §"Tutorial example
  selector"** — workspace attribute `LuauUI_Example = 1..7`, the module is required,
  `build()` is called, and examples 1–4 are presented by the caller while 5–7 present
  themselves. A theme picker is mounted beside them.
- **There is no `examples` scenario.** `examples/gallery/scenarios/init.luau` registers
  22 names; none of them mounts a tutorial example, so today the seven examples are
  outside the machine-readable verification surface (`report`/`step`/`reset`/`setEnv`)
  that every other stage's evidence rides on.
- **The theme drift lint deliberately excludes examples.** `tools/lune/check_theme_drift.luau`
  scans `src/controls`, `src/render/renderer.luau` and `src/present/presenter.luau`
  only, and its header states the exclusion as a policy ("an app author's literal is a
  legitimate opt-out"). Nothing checks example style authority today.
- **The style-owned vocabulary the examples are not using.** `blueprint_schema.luau`
  already accepts a typography ROLE name for `textSize` (`caption|label|body|heading|
  title|control` plus the `strong`/`numeral` weight roles), a spacing STEP or theme
  metric path for `padding`/`gap`/`rowGap`, and a metric path in every numeric field of
  a `dim` (`px`/`min`/`max`/`preferred`). `UI.Grid` ships with `columns`,
  `minColumnWidth = "intrinsic"` and `itemSizing = "uniform"`.
  Against that surface the current examples carry, by grep: `textSize = 24|14|16|20|28|
  26|18` literals in all seven, `padding = 16`/`gap = 4|6|8|12|16` literals in all seven,
  `{ type = "fixed", px = 48 }` word-game tiles, `px = 44` tile-game cells, `px = 40/48`
  rack tiles, `px = 70` and `px = 144` playlist columns, and a `sizeClass`→`40|56|72`
  branch computed inside `07_match3`. Only `04_confirm_dialog` uses the semantic form
  (`padding = "m"`, `gap = "s"`).
- **Boards are hand-rolled `VStack` of `HStack` of fixed-px cells** in 05, 06 and 07,
  not `UI.Grid`.
- **Example 03 has no player-reachable server.** `server.flush()` and `mutation.reject`
  are returned as test handles only; the screen has a Toggle, a ±stepper and a status
  line. An interactive player can reach `pending` and nothing else — no accept, no
  reject, no reason, no rollback, no reset.
- **Example 05 is missing most of the plan's mechanics.** It has a 6×5 board, active-row
  entry, exact/present/absent two-pass scoring and a win/loss modal. It has **no**
  dictionary, no short/invalid rejection feedback, no on-screen keyboard state, no
  restart, no non-color cue, and its results-modal `Close` button carries **no
  `onActivate`** — once the modal opens there is no way to dismiss it.
- **Example 06 has no instructions, no invalid-move feedback, no completion and no
  reset**; a player who places all seven rack tiles reaches a dead end.
- **Example 07 builds its opening board from `nextKind()` per cell and never calls
  `resolve()`**, so the start state can contain a pre-existing match; it has no score,
  no progress, no reset, no no-moves detection, and its image path models `pending` but
  not failure.
- **Example 04 shows the player nothing after Confirm or Cancel** — `result` is a test
  handle — and offers no way to restore the deleted save.
- `LuauUI.VERSION = "0.8.0"`. Suite at stage start = **3442** passing
  (`./run-tests.sh`, 2026-08-06).
- Studio available: one instance, `LUIPerfLab`. `tools/studio/inject.luau` builds the
  gallery tree (`LuauUI`, `LuauUIExamples`, `LuauUIScenarios`, `StarterPlayerScripts.Gallery`)
  into whatever place is open, so the example rows can be driven from it.

## Rows

| ID | User-visible behavior | Risk while lower tests stay green | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **EQ-1** | Each of the seven examples, opened by someone who has never read its source, states its lesson on screen, shows what to do first, gives visible feedback for success, failure and unavailable actions, and offers completion plus reset/restart | A tutorial that only its author can follow: every control works, every test passes, and a new reader cannot tell what to press | E3 play-through per example | Play each example in a visible Studio session and fill the audit matrix | `artifacts/example-quality-pass/audit.md` | PASS_AUTOMATED |
| **EQ-2** | Example code is domain/content logic plus declarative LuauUI composition — no raw `Instance` construction, no direct UI input routing, no platform-name branch, no imperative responsive geometry, no parallel focus graph, no copied control state, and no animation bypassing the framework model | A "fixed" example that works only because it reimplements adaptation locally, leaving the framework bug in place for the next screen | E0 ledger + E1 tests for each framework fix | Ownership ledger classifying every helper, bypass and device branch found or proposed; framework-owned needs fixed behind a public API with tests and docs | `artifacts/example-quality-pass/ownership-ledger.md` | PASS_AUTOMATED |
| **EQ-3** | Every style-authority property in every example resolves from the active theme package: typography roles rather than px text sizes, spacing steps or metric paths rather than literal padding/gap, theme metrics rather than fixed cell sizes, and semantic roles/tags rather than raw state colors | 24 is still 24 under Studio Neutral, so a literal passes every test and silently makes that example immune to every theme | E1 + E3 | The drift check below plus a themed capture pair per example | drift report + captures | PASS_AUTOMATED |
| **EQ-4** | A property-authority-aware drift check fails on direct writes/literals for style-owned properties, unknown semantic roles and example adapter writes, while allowing documented content and structural constants — and it has been seen to fail | A broad "ban every number" grep is unrunnable and gets suppressed; a check nobody has watched bite is decoration | E1, mutation-tested | New example-scoped check extending `tools/lune/check_theme_drift.luau`, with a recorded mutation proof | `artifacts/example-quality-pass/drift.json` | PASS_AUTOMATED |
| **EQ-5** | Swapping the theme package at runtime restyles **and reflows** all seven examples — palette, typography/control metrics and bounded chrome — with no source edit and no remount | A "theme swap" that only recolors, or that silently rebuilds the tree (losing focus, scroll and mount identity) | E3 paired captures + mount/focus identity | Studio Neutral ↔ Fantasy Parchment swap in the mounted example, with package/snapshot, effective font/metrics, decoration layers, focus and mount identity recorded either side | `artifacts/example-quality-pass/studio/theme-swap.json` + captures | PASS_AUTOMATED |
| **EQ-6** | All seven remain readable and operable at `PreferredTextSize` `Medium` and `Largest` under the Step 8.5 overflow order (reflow → scroll → bounded truncation with full-value access), with no overlap and no inaccessible essential text | Large text is the single most common device-only divergence; a dev-viewport screenshot cannot see it | E1 sweep + E3 on compact phone portrait/landscape | Preferred-text axis over the examples scenario, paired with geometry and the disclosure diagnostics | `artifacts/example-quality-pass/studio/large-text.json` + captures | PASS_AUTOMATED |
| **EQ-7** | In example 03 a player with no source access can trigger an intentionally **accepted** change, see the optimistic value apply immediately, see the request is pending, deliver/observe acceptance, and watch draft and authoritative values reconcile | The lesson is reachable only from a test handle, so the running example teaches half a state machine | E1 transitions + E3 live play | Play the accept path through pointer and through focus-based keyboard activation | `artifacts/example-quality-pass/studio/ex03.json` + captures | PASS_AUTOMATED |
| **EQ-8** | In example 03 a player can trigger an intentionally **rejected** change, see the optimistic value, then the rejection reason and the rollback to server truth, read a short visible event history, and reset the demonstration | A rollback that happens with no visible reason reads as a bug, not a lesson | E1 + E3 | Same session, reject path plus reset, with the history text captured | same | PASS_AUTOMATED |
| **EQ-9** | Example 05's pure rules are correct: duplicate-letter budgeting in two passes, short and invalid guesses rejected visibly without consuming a row, submitted rows retained, on-screen key state monotonic by strongest result, win, loss with solution revealed, input disabled after the end except restart/dismiss, deterministic seeded restart | Wordle duplicate scoring is the classic silently-wrong rule; the linked article deliberately gets it wrong, and a board that looks plausible hides it | E1, failing-first | Pure scoring/state-machine tests over multiple duplicate patterns, invalid/short guesses, key precedence, row consumption, win, loss and restart | suite | PASS_AUTOMATED |
| **EQ-10** | The mounted example 05 is playable through hardware letter/Backspace/Enter, pointer and touch activation of on-screen keys, keyboard focus navigation + activation of on-screen keys, gamepad navigation/A/B with ten-foot focus, and switching live input classes mid-guess without losing the active guess | Calling `typeLetter`/`submit` proves the model, not the input path — the two have diverged before | E3 native/injected input per row; gamepad delivery stays E4 | `VirtualInput` keys and pointer from live geometry, paired with raw event, semantic action and board state; gamepad rows recorded as synthetic-navigation only | `artifacts/example-quality-pass/studio/ex05.json` + traces | PASS_AUTOMATED |
| **EQ-11** | Example 06 plays a meaningful loop from a fresh start: instructions and selectable state visible, activation selects the tile the player expects, invalid moves explain themselves and leave state consistent, progress/completion visible, and reset available | A board algorithm that is correct while the game is unplayable — no way to tell what is selected, no way to start over | E1 gameplay tests + E3 play-through | Play from fresh start through completion and reset; add a test for every defect found | `artifacts/example-quality-pass/studio/games.json` (`example06`) + captures | PASS_AUTOMATED |
| **EQ-12** | Example 07 plays a meaningful loop: swaps resolve matches, gravity, refill and chained matches deterministically; the opening board is neither pre-matched nor immediately stuck; image pending **and failure** states are visible and recoverable; progress and reset exist | The opening board is generated cell-by-cell with no resolve pass, so a seeded start can already contain a match the player never made | E1 + E3 | Deterministic board tests incl. the opening-board invariant and chain resolution; live play-through | `artifacts/example-quality-pass/studio/games.json` (`example07`) + captures | PASS_AUTOMATED |
| **EQ-13** | Examples 01, 02 and 04 teach their advertised lesson with no misleading copy, no dead end, a reset path, no style bypass, and no layout or input failure — at their original small scope | Example 04 records its outcome only into a test handle, so confirming or cancelling changes nothing the player can see | E3 play-through | Play each through its advertised lesson | `artifacts/example-quality-pass/audit.md` + captures | PASS_AUTOMATED |
| **EQ-14** | All seven examples lay out correctly across the canonical five view rows, with the device preset resolved at runtime and its exact configuration recorded per row | A layout proved only at the developer viewport; a row that silently stayed portrait and was recorded as landscape | E3, emulation-labeled | `tools/studio/device_matrix.luau` over the new examples scenario, presets from `StudioDeviceSimulatorService`, configurations recorded | `artifacts/example-quality-pass/studio/device-matrix.json` | PASS_AUTOMATED |
| **EQ-15** | Supported keyboard and pointer gameplay paths are driven with `VirtualInput` from live geometry, and each raw/native event is paired with the semantic action and the visible state change it caused | A screenshot can look correctly aimed while the routed input landed elsewhere; a fired binding proves the downstream action only | E3 raw-input traces | `VirtualInput` Tab/Shift+Tab, Space/Return, arrows, text and mouse over the mounted examples; unsupported paths recorded `FAIL_ENVIRONMENT`, never relabeled | same | FAIL_ENVIRONMENT |
| **EQ-16** | Playing and dismissing every example leaves clean Studio output and no retained work: instances, connections, reactive nodes and action contexts return to the pre-mount census | A leak that only shows after the eighth demo switch; an example whose modal survives its own teardown | E1 + E3 census | Mount/dispose census per example, before and after, in a live session | `artifacts/example-quality-pass/studio/lifecycle.json` | PASS_AUTOMATED |
| **EQ-17** | Rapid input and reset leave no stale selection, focus, resource handle or bound action in any example | A reset that clears the model and leaves the focus ring on a node that no longer exists | E1 stress tests + E3 | Rapid-input and reset-mid-flight tests per game example, plus a live drive | suite + studio artifact | PASS_AUTOMATED |
| **EQ-18** | Every standalone example place rebuilds from clean source and contains the current example modules | A place file that is the right size and carries last week's example | E0 build + E1 tree inspection | `tools/build_places.sh` then a tree assertion over the emitted `.rbxl` files | `artifacts/example-quality-pass/places.json` | PASS_AUTOMATED |
| **EQ-19** | Each example's source header and the tutorial guide describe what the player actually sees, and the guide/inventory list the current seven | A header promising a lesson the example no longer teaches is worse than no header | E0 | Guide + header review bound by a docs check | `docs/guide/04-tutorial-examples.md` + headers | PASS_AUTOMATED |
| **EQ-20** | Registered tests strictly increased, the full library suite is green, and the standard registration/docs/boundary/prop-parity/surface-ledger/manifest-integrity/stylua battery plus the prior phase gates pass at the final source | A stage that passes its own gate and reddens two others | E1 | `tools/test.sh`, the standard battery, `tools/prior_gates.sh` | `artifacts/test.json`, `artifacts/example-quality-pass/prior-gates.txt` | PASS_AUTOMATED |
| **EQ-21** | Rascal Rally consumer lockstep: every LuauUI source/contract/default/behavior/asset change this stage makes is audited against game callers, the game suite is green at the judged source, and either the game integration is updated or the reason no caller change was correct is recorded | A "compatible" framework change that the production consumer disagrees with | E1 + E3 where visible | Consumer-impact ledger + live game suite | `artifacts/example-quality-pass/consumer-impact.md` | FAIL_ENVIRONMENT |
| **EQ-22** | The required fresh-context phase-gate review (plus architecture and/or Roblox-platform review if this stage changed those authorities) ran against the raw artifacts, and every requirement-affecting finding is fixed or explicitly dispositioned | The implementer's own conclusions substituted for an independent read | E0/E1 | Reviewer reports + dispositions | `artifacts/example-quality-pass/reviews/` | PASS_AUTOMATED |
| **EQ-P1** | Physical touch on a real phone: tap targeting, gestures and touch feel across the seven examples, and the real mobile OS keyboard in 01/02/05 | The emulator cannot make the engine report `preferredInput = Touch`, and it never summons the OS keyboard | E4 | Review packet's device procedure on named hardware | operator result | PENDING_PHYSICAL |
| **EQ-P2** | Physical gamepad/console: real `PreferredInput == Gamepad` delivery, Button A contention and ten-foot focus visibility across the game examples | Studio cannot synthesize a true gamepad input class; synthetic KeyCodes prove navigation logic only | E4 | Review packet's console procedure on named hardware | operator result | PENDING_PHYSICAL |
| **EQ-P3** | The seven read as **one designed product** under both theme packages — hierarchy, density, readability and pacing — judged against the captures | Coherence is not a property any assertion can hold | E5 | Director/UI-designer review of the capture set | review result | PENDING_HUMAN |


## Closing notes (2026-08-06)

### Framework and host defects this stage found by PLAYING, and fixed

| ID | Defect | Fixed in | Pinned by |
|---|---|---|---|
| F-1 | A **bound** enum value outside its closed set was accepted and painted nothing — all 30 word-game board tiles rendered at `BackgroundTransparency = 1` | `src/render/renderer.luau` `assertEnumValue` | `tests/authoring.spec.luau` (first render, later set, and a legal value unaffected) |
| F-2 | `UI.Grid` trapped focus: its first row had no `up` exit and its last no `down`, and `containment` blocks fall-through, so nothing after a grid was reachable by arrows or D-pad | `src/present/focus_map.luau` `linkGridBoundaries` | `tests/auto_input_screens.spec.luau` (exit both ways, inner nav unchanged, adjacent grids, and a lone grid still contained) |
| F-3 | `MouseButton1Up` referenced an undeclared `scale` — a nil global — so every bespoke-path button press threw and the pressed dip never recovered on release | `src/client/screen_target.luau` `recoverPressDip` | Studio console clean on re-run |
| F-4 | `newTable`'s `rowGap` rejected a theme metric name, unlike its sibling `cellPadding` and unlike `UI.Grid.rowGap`, because it is read in Luau arithmetic | `src/controls/table.luau` `rowGapPx` | `tests/table.spec.luau` §"Table.rowGap" |
| F-5 | A run of spaces measured as ONE space: `"a   b"` reserved the same box as `"a b"`. Measured on the engine at BuilderSans 12, the word-game legend draws 134.5 px and the model reserved 124.5 — four spaces at 2.5 px, exactly — so a label truncated with 780 px free beside it | `src/layout/text_metrics.luau` | `tests/text_calibration.spec.luau` §"consecutive spaces" |
| F-6 | A rating star's width cap was an UNSCALED metric while its glyph paints at `textSize * typographyScale`; at the ten-foot 1.5x every star in the playlist reported `textFits = false` | `src/controls/rating.luau` (`hug`) | device-matrix console row, re-measured `fits = true` |
| H-1 | The theme picker covered the example it exists to restyle (panel `x 339..899` over example 01's field `x 16..891`; the whole screen on a phone) | `theme_picker.luau` + `init.client.luau` | `tests/gallery_theme_picker.spec.luau` §"standalone collapsed shell" |
| H-2 | `Tab` bound nothing in the gallery — `keyboardNavigation` defaults false and was never opted into, in a bootstrap that disables the CoreGui players list precisely so Tab can reach a developer InputContext | `init.client.luau` | device-matrix keyboard rows |
| H-3 | The host answered the loopback server every frame, so example 03's `pending` state — the whole lesson — was resolved before a player could see it | example 03 owns delivery; the hook's comment corrected | `tests/examples_gallery.spec.luau` |
| TS-F1 | The theme swap was one-shot: `install` refuses a second controller and RETURNS the reason, so a loop that ignored it kept the first package and reported success | `examples/gallery/scenarios/examples.luau` | `studio/theme-swap.json` |

### EQ-6, the row that was `FAIL_PRODUCT`, and the instrument caveat that still qualifies it

**EQ-6 now passes: 56 of 56 large-text cells** (two phone orientations x two theme
packages x two preferred-text values x seven examples).

- **LT-F2 — six rating stars collapsed to a zero-width box — is FIXED.** An `HStack` that
  cannot fit all its `hug` children clamps in order and starves the tail. `newRating` now
  lays its marks out in a `UI.Grid{ columns = count, itemSizing = "uniform" }`, whose pitch
  is `innerWidth / columns`, so a short offer shrinks every mark evenly instead of dropping
  the last ones. Re-measured at typographyScale 3 in the 144 px column: five stars, each
  20 px, at x = 200/227/254/281/308. Zero collapsed boxes across all 56 cells.
- **LT-F1 is SUPERSEDED** — that fix changed example 02's layout and the hint/header pair
  no longer overlaps.
- **LT-F3 is FIXED (2026-08-06).** `UI.Table`'s header cell was
  `height = { type = "fixed", px = "controls.table.headerHeight" }` — a 28 px CAP. At a
  raised preference a ONE-LINE column title measures 34 px, so the title painted out of its
  own ZStack, up into the auto Edit toolbar and down into the first row. The band is now a
  FLOOR (`minMax` `min`): the token is what a header must never be *shorter* than, and the
  live text facts decide how much taller it has to be — the director's own framing, "if
  height is the issue why can't we make the whole table have more height as text size
  increases". Framework-owned, in `src/controls/table.luau`; example 02 authors no toolbar
  or header geometry.

  **The solver had been saying so the whole time.** `controller.diagnostics()` files
  `/…/Head-<id>/Title :: this child overflows its zstack by 0x6px … give the box room — a
  `minMax` FLOOR rather than a fixed CAP` at +10 and +14. Nothing in the suite *failed* on
  the diagnostics list, so nobody read it (docs/lessons/the-solver-already-told-you.md).
  And the LT-8 control sweep could never have caught it: its Table fixture mounted without
  `reorderable`, so the toolbar the header collided with did not exist in any swept row.
  Both are closed — the fixture now declares `reorderable`, and the first of the three new
  `tests/table.spec.luau` cases asserts the diagnostics list is EMPTY.

  Proof: three new tests over {0,4,10,14} x {compact portrait, compact landscape}, all
  three mutation-proved (reverting the one word `minMax`->`fixed` fails all three). Live
  A/B in one Studio session, pre-fix source injected and measured, then the fix: the three
  column headings went from painted 1 px INSIDE the Edit toggle to clearing it, under both
  reference packages. All four originally-failing cells re-measured at their exact setting:
  zero overlapping pairs, every one clearing by 2 px. See
  `studio/large-text.json` -> `eq6Resolution` and
  `captures/eq6-header-largest-parchment-AFTER.png`.

**Left open, and NOT this defect.** At Largest on a compact phone the `Name` column heading
truncates to `Na...`: the two fixed-width columns grow with the preference and starve the
fill column. That is the column-WIDTH policy, not the header-height overlap, and it is
logged for a later pass rather than folded into this fix.

**The caveat that qualifies every large-text number in this stage.** LuauUI deliberately
splits the text-scale seams (renderer, NS-A9): MEASURE reserves engine-scaled bounds while
PAINT writes only the authored size, because the engine applies the player's preference
itself at draw time. `GuiService.PreferredTextSize` is read-only to scripts, so overriding
the env fact through the scenario's `setEnv` seam moves the RESERVATION and cannot move the
engine's draw-time scaling — measured: example 02's hint reserved a 152 px box while its
text painted at `TextSize 14`, `TextBounds.Y = 14`, `TextFits = true`. So LT-F3 is an
overlap of **reserved boxes**. That still matters, because on real hardware the engine fills
those boxes, but it is not a capture of overlapping glyphs and is not presented as one. The
physical Largest-text row stays `PENDING_PHYSICAL`.

### The fresh-context phase gate REJECTED this stage, and it was right

`artifacts/example-quality-pass/reviews/phase-gate.md` — **verdict REJECT**, 3 BLOCKER, 9 MAJOR,
9 MINOR. Its central charge is correct and is the reason many rows above now read `PENDING` or
`FAIL_ENVIRONMENT` rather than `PASS_AUTOMATED`:

- **BLOCKER-1 — RESOLVED FOR THE THEME ROWS, still open for the play rows.** Fourteen captures now
  exist (`captures/`, seven examples x two packages, desktop-standard), each paired in
  `captures.json` with the facts it shows. That earns EQ-3 and EQ-5 back: every example changed font
  family and type size, every one gained decoration layers, focus identity held on all fourteen and
  the solver reported zero diagnostics on all fourteen. EQ-1, EQ-11, EQ-12 and EQ-13 stay `PENDING`
  because their blocker is BLOCKER-2 (the audit), not the captures. The original finding read:
  **there are no captures.** `find artifacts/example-quality-pass -type f ! -name "*.md"
  ! -name "*.json"` returns nothing. Six rows named captures as their artifact and were marked
  passed anyway. The execution contract is explicit that layout/text/paint rows need geometry
  **plus** a capture. EQ-1, EQ-3, EQ-5, EQ-11, EQ-12 and EQ-13 are demoted to `PENDING`.
- **BLOCKER-2 — `audit.md` is the PRE-implementation audit.** Its per-example verdicts still read
  `FAIL_PRODUCT`, it has no post-fix re-audit, and it contains zero occurrences of `touch`,
  `gamepad`, `tablet`, `landscape` or `ten-foot` — the paradigm and form-factor coverage EQ-1
  demands. The source fixes are real; the evidence for the row is not.
- **BLOCKER-3 — EQ-10 and EQ-15 claim input paths nobody drove.** `studio/ex05.json` is
  pointer-only: no hardware letter/Backspace/Enter, no keyboard focus navigation plus activation,
  no live input-class switch. `studio/device-matrix.json` contains no VirtualInput traces at all,
  only a capability probe listing method names. Worse, the stage already MEASURED that `SendKey`
  cannot insert a character into a focused TextBox (`audit.md`) — which is textbook
  `FAIL_ENVIRONMENT` and was not recorded as one. **EQ-10 is now closed**: all eight input paths were driven with paired raw events — hardware letters, Backspace, Return (the full win typed on hardware keys), arrow navigation, Space on a focused key, Tab traversal, and a keyboard->pointer->keyboard switch that kept one guess. **EQ-15 stays `FAIL_ENVIRONMENT`**: the device-matrix artifact still carries no VirtualInput traces.

  **The horizontal-arrow half of EQ-15 is now DIAGNOSED (2026-08-06).** `Right` always
  arrived `gameProcessed = true`, and the consumer was unidentified because disabling the
  PlayerModule's *controls* module did not free it. The consumer is **`RbxCameraKeypress`** —
  the default `CameraModule`'s keyboard camera-rotation binding, which binds Left/Right/I/O
  and sinks them. One identical `Right` press read `gameProcessed = true` with the binding
  up and `false` after `UnbindAction`, and with the key free, focus walked
  `key_Q -> key_E` across row 1, then `Down` into row 2 and `Left` to `key_S`. **LuauUI's
  2-D arrow navigation is correct; nothing in the framework was consuming the key.** The row
  stays `FAIL_ENVIRONMENT` rather than being relabelled, because in a place running the
  default camera the key genuinely never arrives — that is a consumer's call to make, and
  `docs/reference/api.md` now says so by name. Evidence: `studio/arrow-navigation.json`.
- **MAJOR-1 — the raw-event instrument was dark** for examples 03, 06, 07 and the lifecycle census
  (`InputBegan` counted 0 while the UI responded). The artifacts explained it away by pointing at a
  *different* run against a *different* example. The contract says: mark `FAIL_ENVIRONMENT`, repair,
  rerun. EQ-8, EQ-16 and EQ-17 drop to `PENDING` pending a repaired counter.
- **MAJOR-7 — `acceptance-ledger` is a self-attesting guard.** It greps this file for the status
  column. It verifies that the ledger *says* PASS_AUTOMATED and cannot detect any of the three
  BLOCKERs. That is a real hole in the gate and it is recorded, not closed.
- **MAJOR-6 — `rascalrally-consumer` passes on a ledger that declares its own canary skipped.**
  The ledger's honesty is fine; the check is the defect.

**What the verifier did NOT ask to change:** EQ-6 / LT-F3 was `FAIL_PRODUCT` at review time. It
called the scoping and the instrument caveat "the most rigorous work in this stage" and would not
weaken either. The row was subsequently FIXED at the cause rather than re-scoped — see the EQ-6
section above; the instrument caveat is untouched and still stands.

**Process finding worth keeping (MINOR-9):** the tree was being written while the verifier read it —
its first gate run saw an all-`PENDING` manifest, its second a broken grep. A phase gate should be
handed to acceptance control against a frozen tree.

## Final gate result

`tools/gate.sh example-quality-pass`, run at the judged source (LuauUI suite **3559**, Rascal
Rally **3090**):

**16 of 18 checks PASS.** The two that do not are the two the director released this session:

```
PASS  acceptance-ledger          PASS  lifecycle-and-rapid-input
PASS  play-teaching-matrix       PASS  device-matrix
PASS  ownership-ledger           PASS  places-and-docs
PASS  style-authority-and-drift  PASS  library-suite-green
PASS  theme-package-swap         PASS  prior-gates-unregressed
PASS  large-text-overflow        FAIL_RECOVERABLE  rascalrally-consumer
PASS  example-03-optimistic-sync PASS  fresh-context-reviews
PASS  example-05-word-game       PENDING  physical-and-human-rows
PASS  example-05-native-input
PASS  example-06-07-gameplay
gate: FAIL_RECOVERABLE
```

`large-text-overflow` — the check that carried this stage's one `FAIL_PRODUCT` — is green:
EQ-6 was fixed at the cause, not re-scoped. `prior-gates-unregressed`, registered `PENDING` at
stage start, now REGENERATES the full sweep and passes it (13 PASS/9 FAIL at start → 17 PASS/5
FAIL at close, with the five allow-listed by name as the bench-only set).

**The gate does not exit 0, and that is the correct reading of this source state.** It is held
open by an unopened Studio place and by hardware that is not present — not by anything unproven
in the framework or the examples.

### Ten rows flipped at close, and exactly what each one does NOT cover

The fresh-context phase-gate review demoted eight rows to `PENDING` because the evidence they
named did not yet exist. It does now, and each row's guarding gate check is green, so the rows
were flipped rather than left reading worse than the tree:

`EQ-1`, `EQ-13` (audit.md's POST-FIX RE-AUDIT, 35 of 35 cells), `EQ-7`, `EQ-8` (`studio/ex03.json`),
`EQ-11`, `EQ-12` (`studio/games.json`), `EQ-16`, `EQ-17` (`studio/lifecycle.json`), `EQ-19`
(guide + headers), `EQ-22` (`reviews/`).

Two artifact names in the table were also wrong and are corrected: examples 06 and 07 were
recorded in `studio/games.json`, not in `studio/ex06.json` / `studio/ex07.json`, which never
existed. A ledger that points at a file nobody can open is the same defect as a check that
proves nothing.

**What the flips do not cover.** Every one of these is E1–E3 — headless, or Studio-injected
through the examples scenario with `VirtualInput`. **Touch is `PENDING_PHYSICAL` for every
example and gamepad is synthetic-navigation-only**, and neither is relabelled: that coverage is
carried by `EQ-P1` and `EQ-P2` below, which stay open. `audit.md` carries its own explicit
"What this re-audit does NOT close" section for the same reason.

### Also still open — and why the gate cannot reach exit 0 in this session

**EQ-21 is `FAIL_ENVIRONMENT`, not `PENDING`.** The Rascal Rally consumer audit ran, the game
suite is green at the judged source (3090), and a new game-side test proves the one layout
change with a plausible consequence cannot reach the live screen. What did not run is the
Studio canary, and it *cannot*: the only connected Studio instance is `LUIPerfLab` and nothing
in the toolchain opens a different place.

**The director ruled on it on 2026-08-06:** *"I can't access my computer right now so we'll
have to proceed without rascal rally or a human test."*

So three rows are deferred with authorization and are **not** closed:

| Row | State | What would close it |
|---|---|---|
| `EQ-21` | `FAIL_ENVIRONMENT` | the Rascal Rally place open in Studio, one Sponsor session driven |
| `EQ-P1` / `EQ-P2` | `PENDING_PHYSICAL` | a real phone and a real gamepad; Studio emulation may not substitute |
| `EQ-P3` | `PENDING_HUMAN` | a director/UI-designer read of the capture set |

**The gate checks that demand them are deliberately left RED rather than rewritten to accept
their absence.** A check that stops asking for the canary would never ask again — that is the
`can't-ever-fail` shape this repo has removed twice already. `tools/gate.sh
example-quality-pass` therefore does not exit 0, and the reason it does not is these three
rows, not an open product defect: **EQ-6, the one `FAIL_PRODUCT` in this stage, is fixed and
its check is green.**
