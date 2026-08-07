# Play audit of all seven tutorial examples (EQ-1, EQ-13)

**Session:** 2026-08-06, Studio `LUIPerfLab` place, gallery tree injected from
`tools/studio/inject.luau` at source stamp `b5212807-3155338`.
**Method:** one Play session per example (`workspace.LuauUI_Example = 1..7`), the real
gallery bootstrap and the real adapter. Every claim below is a tool result from this
run — geometry read from the flat instance map, input driven with `VirtualInput`,
captures stored beside this file.

## Studio preflight (execution contract §4)

| Item | Value |
|---|---|
| Studio instance | `LUIPerfLab` (`a31d5f1c-6baf-4d5b-bcf7-20d4869f6faf`) |
| Source stamp | `b5212807-3155338`, injected this session, 161 nodes (36 created, 36 patched) |
| Play mode | Play Solo, focused client |
| Viewport | `907 × 1044`, GUI inset `0, 58`, screen root `907 × 986` |
| Device simulation | inherited `samsung_galaxy_s22_ultra` from a previous session → **stopped** (`StopSimulationAsync`) before the audit; every row below is the unsimulated desktop viewport |
| Mount | exactly one `LuauUI_*` ScreenGui per example plus the theme picker |
| Canary | pointer click and `SendKey` both produced raw `InputBegan` events with the intended effect |

### Two instrument facts this session established

1. **Injected pointer coordinates are in viewport space; GUI geometry is inset space.**
   Injecting `y = 100` was reported by the engine as `y = 42` — exactly the `58 px`
   `GuiService:GetGuiInset().Y`. Every click below is injected at
   `AbsolutePosition + AbsoluteSize/2 + GetGuiInset()`. Aiming without the inset silently
   lands one control higher and looks like "the control is dead".
2. **`VirtualInput:SendTextInput` works, but only into an already-focused `TextBox`.**
   Called with nothing focused it succeeds and does nothing (this is why an earlier
   attempt read as "text injection is unavailable"). Called after a calibrated click on
   the field it typed `212` and the live preview recomputed. `SendKey` with a *letter/
   digit* KeyCode delivers a raw keyboard event but does **not** insert a character into
   a focused TextBox, and `KeyCode.One` is refused outright
   (*"permanently bound to a CoreGUI core action"*) even with the Backpack CoreGui
   disabled. Digits must go through `SendTextInput`.

## The whole-gallery defects (hit every example)

| ID | Defect | Evidence |
|---|---|---|
| **A-1** | **The theme picker overlays and occludes the example.** The example path calls `mountThemePicker()` with `collapsible` unset, so the panel is presented permanently expanded at `DisplayOrder 10200`. Measured on example 01: panel rect `x 339..899, y 8..219`; the temperature field rect `x 16..891, y 78..122`. The picker covers the field from `x = 339` to `x = 891` — most of the primary control of example 01 is unreachable. On a `360 × 691` phone the panel covers the example **entirely**. The showcase path already passes `collapsible = true`; the example path does not. | `ex01_portrait`, `ex01_desktop` captures + geometry dump |
| **A-2** | **Every example floats transparently over the 3D world.** No example root declares a `surface`, so titles and secondary text sit on sky-blue with no plate. `role = "secondary"` copy ("Enter a temperature in °F:", the playlist hint) is the least legible text on screen. Example 04's dialog got `surface = "scrim"` + `raised` after a device report; that lesson was never applied to the other six. | all seven captures |
| **A-3** | **`MouseButton1Up` throws on every bespoke-path button press.** `src/client/screen_target.luau:1271` calls `TweenService:Create(scale, …)` where `scale` is **not declared in that scope** — it resolves to a nil global. The sibling `MouseLeave` handler (line 1242) and the native-path `recover()` (line 847) both read `handle.motionScale or handle.uiScale` and nil-guard; this one does neither. Two clicks in example 07 produced exactly two `TweenService:Create failed because Instance is null` errors. The pressed dip therefore also never recovers on release. **Framework-owned.** | Studio console output, example 07 |
| **A-4** | **Style authority is bypassed in all seven.** Every example writes literal `textSize` px (24/28/26/20/18/16/14), literal `padding`/`gap`, and literal `{type="fixed", px=…}` cell sizes, although the schema already accepts typography roles, spacing steps and theme metric paths. Only `04_confirm_dialog` uses the semantic form. Verified in the running tree: example 01's `Title` painted `TextSize 24`, `Prompt` `14`, `Result` `20` — the literals, not a role. | geometry dump, all examples |

## Per-example rows

### 01 — Temperature Converter

| Question | Observed |
|---|---|
| Lesson promised | signals, a derived memo bound to a Text, and a `UI.TextInput`'s LIVE (`onChange`) vs COMMIT (`onCommit`) modes |
| Startup | title, prompt, an empty field with placeholder `e.g. 212`, `Preview: —`, `Result: —` |
| First action | type in the field — but see **A-1**: most of the field is under the theme picker |
| Success feedback | **works.** Calibrated click focused `/TempConverter/Fahrenheit/Field`; `SendTextInput("212")` produced `Preview: 117878 °C (live, as you type)` for `212212` — the live path is real and native-driven |
| Failure feedback | none needed; `validate` silently refuses non-numeric text (correct) |
| Completion / reset | **none.** No way to clear the field or return to the starting state except selecting all and deleting |
| Style | `textSize` 24/14/16/20 literals, `padding = 16`, `gap = 8` — **A-4** |
| Verdict | lesson intact, blocked by **A-1**, missing reset, style bypass |

### 02 — Playlist Table

| Question | Observed |
|---|---|
| Lesson | Table control, custom interactive cell (rating), filter-as-you-type, drag reorder |
| Startup | title, filter field, hint line, header + six rows with stars and lengths — reads correctly |
| Feedback | selectable rows, star run, `clearButton`; the hint states all three interactions |
| Completion / reset | **none.** No way to restore the original order or ratings after experimenting |
| Style | `textSize` 24/14, `padding = 16`, `gap = 8`, `rowGap = 2`, `px = 70`, `px = 144` — **A-4**. The `px = 144` rating column carries a documented framework follow-up (a table column cannot hug across header **and** body), which belongs in the ownership ledger |
| Verdict | the strongest of the seven; needs reset, style authority, and **A-1**/**A-2** |

### 03 — Settings Sync — **FAIL_PRODUCT**

| Question | Observed |
|---|---|
| Lesson promised | optimistic apply → validated mutation → reconcile **or** rollback |
| Startup | `Audio Settings`, a Music toggle, `– Volume: 10 +`, `Status: idle` |
| Live drive | clicked `+` once → `Volume: 11`, `Status: pending`. Clicked `+` again → **unchanged**. Waited 2 s → **still `Volume: 11`, `Status: pending`** |
| Accept path | **unreachable.** `server.flush()` is a returned test handle with no control on screen |
| Reject path | **unreachable.** The rejection reason string is built and never displayed |
| Rollback | **never observed** |
| Reset | **none** |
| Layout | `Volume: 10` sits at `y 89 h 20` between two `h 46` buttons — the readout is top-aligned against the stepper buttons, not centred |
| Verdict | the example teaches exactly one of the three states it advertises and then dead-ends permanently. This is the plan's named example-03 defect, confirmed live |

### 04 — Confirmation Dialog — **FAIL_PRODUCT**

| Question | Observed |
|---|---|
| Lesson | modal presentation, focus trap, cancel routing, focus restoration |
| Startup | `Save Slot 1` + `Delete Save` |
| Modal | opens correctly with scrim + raised card, dismisses on either button, reopens cleanly, teardown leaves only the base screen |
| Outcome feedback | **none.** After confirming a destructive "Delete", the screen is byte-identical to before: `Save Slot 1` / `Delete Save`. Same after Cancel. The `result` signal is a test handle only |
| Reset | not applicable — but nothing ever changes, so nothing needs restoring |
| Centring | the dialog declares `alignH = "center", alignV = "center"` on a `UI.Screen`. Those props are **documented as ZStack-child alignment** and are silently ignored on a Screen: the card renders at `16,16` (top-left), not centred. Accepted-and-ignored — the exact defect class the roadmap has hit before |
| Verdict | the modal machinery works; the lesson has no visible outcome, and the dialog is not centred |

### 05 — Word Game — **FAIL_PRODUCT (board invisible)**

| Question | Observed |
|---|---|
| Startup | `LuauUI Wordle`, then **~310 px of nothing**, then the three keyboard rows |
| Board | **every one of the 30 tiles is `BackgroundTransparency = 1`.** The tiles occupy correct geometry (`48 × 48` at `16,66` … `224,326`) and paint nothing at all. Cause: the tiles bind `surface` to `"tileEmpty" / "tileFilled" / "tileAbsent" / "tilePresent" / "tileCorrect"`, which are **not** members of the closed `surface` enum (`base|raised|control|chip|badge|accent|scrim|plain`). The schema enum-checks a *static* value; a *bound* value outside the enum is accepted and silently paints nothing |
| Playability | a player sees a title, a void, and a keyboard. There is no visible board to type into |
| Mechanics missing vs plan | no accepted-guess dictionary, no solution list, no short/invalid-guess rejection, no on-screen key state, no restart, no non-color cue |
| Results modal | its `Close` button carries **no `onActivate`** — once the modal opens, nothing dismisses it |
| Style | `px = 48` tiles, `textSize` 28/24/26/16, `gap` 4/16, `padding` 16 — **A-4** |
| Verdict | the plan's named example-05 rebuild is required, and the invisible board is a hard blocker on top of it |

### 06 — Tile Game — **FAIL_PRODUCT (silent invalid moves)**

| Question | Observed |
|---|---|
| Startup | `LuauUI Tiles`, `Score: 0`, a 5×5 grid of empty dark cells, a rack `C A T E R S D` |
| Instructions | **none.** Nothing on screen says "pick a rack tile, then a board cell" |
| Core loop | **works.** Clicked rack slot 1 → it tinted selected; clicked board `1,1` → `C` placed, `Score: 3`, rack slot 1 blanked |
| Invalid move — place with nothing selected | **completely silent.** No message, no state change |
| Invalid move — place on an occupied cell | **completely silent**, and the selected rack tile (`A`) **stays selected** with no explanation of why the placement did nothing |
| Spent rack tile | still renders as a normal-looking empty button; clicking it does nothing and says nothing |
| Completion / progress / reset | **none.** `Score: 3` against no goal; after seven placements the game simply stops |
| Style | `px = 44` cells, `px = 40 × 48` rack tiles, `textSize` 28/18 — **A-4** |
| Verdict | plays, teaches nothing, explains nothing, and cannot be restarted |

### 07 — Match-3 — **FAIL_PRODUCT (all tiles identical)**

| Question | Observed |
|---|---|
| Startup | `LuauUI Match-3` and a 6×6 grid of **visually identical** dark tiles |
| Images | **every tile reads `Image = "rbxassetid://1000000000"`** — the `assets.pending` placeholder — and never changes. The resource provider is acquired but the header states "the provider is drained by the caller", and the gallery bootstrap never drains it. A real player therefore never sees a single tile picture, and cannot tell any two tiles apart |
| Playability | with no distinguishable kinds the game cannot be played at all |
| Selection | tapping `1,1` tinted it selected; tapping the adjacent `1,2` left `1,2` selected rather than clearing the selection after a swap — the swap outcome could not be confirmed from the screen because every tile looks the same. Needs instrumentation before it can be called correct or incorrect |
| Opening board | built cell-by-cell from `nextKind()` with **no `resolve()` pass**, so a seeded start can contain a match the player never made (the plan explicitly forbids this) |
| Failure state | the image path models `pending` but has no failure/retry state |
| Progress / reset | **none** |
| Adaptive sizing | the example itself branches `sizeClass → 40 / 56 / 72 px`. That is imperative responsive geometry inside an example — the plan assigns adaptation to LuauUI |
| Console | two `TweenService:Create failed because Instance is null` errors, one per click — **A-3** |
| Verdict | unplayable as shipped |

## Summary

| Example | Plays? | Teaches its lesson? | Reset? | Style authority? | Blocking defects |
|---|---|---|---|---|---|
| 01 Temperature | partly (A-1) | yes | no | no | A-1, A-2, A-4, no reset |
| 02 Playlist | yes | yes | no | no | A-1, A-2, A-4, no reset |
| 03 Settings sync | dead-ends | **no** | no | no | accept/reject/rollback/reset unreachable |
| 04 Confirm dialog | yes | **no visible outcome** | n/a | partly | no outcome, not centred |
| 05 Word game | **no** | **no** | no | no | invisible board, missing mechanics, dead Close |
| 06 Tile game | yes | **no** | no | no | no instructions, silent invalid moves, no reset |
| 07 Match-3 | **no** | **no** | no | no | identical tiles, unresolved images, pre-matched start |

Zero of seven currently satisfy EQ-1. Four of seven are unplayable or dead-ending.
Three defects (**A-1**, **A-3**, and the accepted-and-ignored `surface`/`alignH` classes)
are framework- or gallery-owned and are carried into
`artifacts/example-quality-pass/ownership-ledger.md`.

---

# POST-FIX RE-AUDIT (2026-08-06, after every fix in this stage)

Everything above this line is the **pre-implementation** audit: its per-example verdicts are the
defects this stage was opened to fix, and they are left exactly as they were measured. The
fresh-context phase gate was right that those verdicts cannot close EQ-1 — a `FAIL_PRODUCT` heading
is not a passing row. This section is the re-audit, and **every cell names the artifact it came
from**. A cell that was not measured says so; none is inferred from a sibling.

## Form factors — all seven examples, all five canonical views

Source: `studio/device-matrix.json`, five rows resolved at runtime through
`StudioDeviceSimulatorService` with each returned configuration recorded.

| Example | Phone portrait 360×691 | Phone landscape 678×339 | Tablet 1080×810 | Desktop 1280×720 | Console ten-foot 1920×1080 |
|---|---|---|---|---|---|
| 01 Temperature | PASS | PASS | PASS | PASS | PASS |
| 02 Playlist | PASS | PASS | PASS | PASS | PASS ¹ |
| 03 Settings sync | PASS | PASS | PASS | PASS | PASS |
| 04 Confirm dialog | PASS | PASS | PASS | PASS | PASS |
| 05 Word game | PASS | PASS | PASS | PASS | PASS |
| 06 Tile game | PASS | PASS | PASS | PASS | PASS |
| 07 Match-3 | PASS | PASS | PASS | PASS | PASS |

**35 of 35 cells pass.** Each requires: zero solver diagnostics, zero off-screen nodes, zero unfit
text, and `judgedTrees > 0` over LuauUI's own ScreenGuis. `sizeClass` resolved compact / regular /
wide / wide / regular; the console row reported `typographyScale 1.5`, `distanceProfile ten-foot`,
`preferredInput Gamepad` and overscan insets 60/90/90/60.

¹ This row **found a defect and it was fixed**: 20 rating stars reported `textFits = false` at
1.5× because the star's width cap was an unscaled metric while the glyph paints scaled. See
`ownership-ledger.md` F-6. Re-measured after the fix: star box 17 px, `TextBounds` 16.5, `TextFits`
true.

## Input paradigms

The four paradigms are **not** equally evidenced, and this table says which is which rather than
averaging them.

| Example | Pointer (mouse) | Keyboard | Touch | Gamepad |
|---|---|---|---|---|
| 01 Temperature | **LIVE** — calibrated click focused the field, `SendTextInput` typed `212`, live preview recomputed | headless suite | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |
| 02 Playlist | headless suite | headless suite | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |
| 03 Settings sync | **LIVE** — all six states driven by mouse press (`studio/ex03.json`) | not driven live ² | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |
| 04 Confirm dialog | headless suite | headless suite | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |
| 05 Word game | **LIVE** — 12 raw `MouseButton1` events | **LIVE** — hardware letters, Backspace, Return (full win), arrows, Space on a focused key, Tab traversal, and a keyboard→pointer→keyboard switch keeping one guess (`studio/ex05.json`, 8 paths) | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |
| 06 Tile game | **LIVE** — refusals, placement, score, progress, reset (`studio/games.json`) | headless suite | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |
| 07 Match-3 | **LIVE** — refusal, art failure and recovery, reset (`studio/games.json`) | headless suite | PENDING_PHYSICAL | headless suite (synthetic KeyCodes) |

² EQ-7 names pointer **and** focus-based keyboard activation. Only pointer was driven for example
03, and that row is `PENDING` in the ledger because of it.

**Touch is PENDING_PHYSICAL for every example, without exception.** The emulator reported
`preferredInput = Touch` on the phone and tablet rows, and that is *not* physical touch: it does not
prove tap targeting, gestures, touch feel, or the mobile operating-system keyboard. **Gamepad is
headless-only**: the suite drives synthetic KeyCodes, which prove the navigation and activation
logic and prove nothing about delivery, platform arbitration or Button A contention. Neither is
relabelled anywhere in this stage.

## Teaching, feedback and reset — the EQ-1 questions, re-answered

| Example | Lesson stated on screen | First action obvious | Success feedback | Failure/refusal feedback | Completion | Reset |
|---|---|---|---|---|---|---|
| 01 Temperature | title + prompt | placeholder `e.g. 212` | live preview and committed Result | `validate` silently refuses non-numeric | n/a | **Clear** |
| 02 Playlist | title + hint naming all three interactions | filter field takes initial focus | rows filter, stars fill, rows reorder | reorder refused while filtering | n/a | **Restore the original playlist** |
| 03 Settings sync | title + a hint line naming the next action | hint says "Change a setting to send a request." | `Status: accepted`, values reconcile, revision advances | `Status: rejected (volume must be 0..10)` + rollback + history | n/a | **Reset demo** |
| 04 Confirm dialog | slot label + outcome line | one Delete button | slot empties, "Deleted." | n/a | slot empty, Delete disabled | **Restore the save** |
| 05 Word game | title + status + a legend | status names the row | tiles score with colour **and** a mark | "Not enough letters — 2 of 5", "not in this tutorial's word list" | win/loss card, word revealed | **New game**, seeded |
| 06 Tile game | title + instruction line | "Pick a letter from your rack…" | score, `n of 7 tiles placed` | "Row 1, column 1 already has a letter." | rack empties, message says so | **Start over** |
| 07 Match-3 | title + instruction line | "Tap a tile, then tap a tile next to it…" | `Cleared n tiles`, score, swap count | "Tiles have to touch to swap.", "That swap makes no run of three." | board re-deals when no move remains | **New board**, seeded |

Every cell above is a string read out of the live tree or asserted by a registered test.

## Theme coverage

Source: `captures.json` — 14 captures, seven examples × two packages, each paired with the facts it
shows. Every example changed font family (BuilderSans → Fondamento) and type size (24 → 28), every
one gained decoration layers, focus identity held on all fourteen, solver diagnostics zero on all
fourteen.

## What this re-audit does NOT close

- **Captures exist for `desktop-standard` at `preferredTextSize 1` only.** The other four views and
  the Medium/Largest text axis have geometry and diagnostics recorded (`device-matrix.json`,
  `large-text.json`) but no image.
- **Touch and gamepad remain `PENDING_PHYSICAL` for all seven.**
- **Example 02 and 04 were not re-driven live post-fix**; their pointer and keyboard cells rest on
  the registered suite.
- **EQ-6 is `FAIL_PRODUCT`** — `LT-F3`, the `UI.Table` toolbar/header overlap at Largest text.
