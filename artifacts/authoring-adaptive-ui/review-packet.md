# authoring-adaptive-ui review packet

**Date:** 2026-07-24 · One focused pass, no test-case discovery required.
Contract §8: complete every automatable row first, then hand over one review build and
one ordered checklist.

**Read `HANDBACK.md` first.** Milestones 0, A and B are delivered with named exceptions;
the five-view matrix and the fresh-context review are closed. This packet covers the one
open live row, two missing captures, one uncovered input class, and the human judgment.

---

## 0. Before anything else — restore the Studio instrument

The last Studio session's play camera reported `1, 1`, which kills injected input and
hangs capture (`docs/lessons/studio-viewport-1x1-instrument-trap.md`). The cause is
outside the agent's reach: the `RobloxStudio` window is minimized or on another macOS
Space.

1. Run `open -a "RobloxStudio"`. That is the recovery that works — `activate` and
   `set frontmost` do not restore a window the window server is not listing. Then keep
   Studio in the foreground for the whole pass; this window did not survive being
   backgrounded.
2. Confirm the instrument:
   ```
   workspace.CurrentCamera.ViewportSize   -- must be larger than 1, 1
   ```
3. If it is still `1, 1`, nothing below can be trusted — stop and say so rather than
   recording a result.

## 1. Build and entry point

```
cd GameStudio/ui/LuauUI
lune run tools/lune/studio_sync          # serves the current source on :8642
```
Then in Studio (Edit datamodel), run `tools/studio/inject.luau` through the MCP, set
`workspace.LuauUI_Scenario`, and press Play. Each scenario prints
`[LuauUI Scenario] '<name>' ready (0.5.0); steps: …` and publishes
`workspace.LuauUIScenarioAPI` (`list` / `steps` / `step` / `report` / `reset` /
`freezeEnv` / `setEnv` — the last drives viewport, insets and display class as declared
test facts, and needs `freezeEnv()` first or the live engine binding overwrites them).

The on-screen build label is the scenario title; `report()` carries
`sourceStamp`, `version`, `viewport`, and the full instance/geometry tree.

## 2. Ordered scenario list

| # | Scenario | Steps to run | Expected result |
|---|---|---|---|
| 1 | `authoring` | `runAllAttempts` | `raised = 9`, `built = 0`. Any `built > 0` is a **failure** — an invalid screen constructed in the shipped library. The screen reads "9/9 invalid screens rejected at construction" and the three grid cells are visible and equal width. |
| 2 | `scroll_host` | `keepVisibleFar`, `keepVisibleAlreadyVisible`, `keepVisibleHorizontal`, `readOffsets` — **this is the one open live row** (`A-SV1` geometry) | `keepVisibleFar.moved = true` with a non-zero `y`; `keepVisibleAlreadyVisible.moved = false` with `y = 0`; `keepVisibleHorizontal.moved = true` with a non-zero `x`. Then confirm in the **tree dump** that each `ScrollingFrame`'s `AbsoluteSize` is non-zero and its `AbsoluteCanvasSize` matches the axis (the horizontal strip's canvas must be wide, not tall). |
| 3 | `scroll_host` | mouse wheel **over** the vertical list (real injection, not a step) | `CanvasPosition.Y` changes and descendants clip at the host edge. This is the native-input half `readOffsets` cannot prove. |
| 4 | `native_style` | unchanged from the previous stage | Regression check only — the reactive-style-hint fix and the sheet rule REORDER (role rules moved after the base fills) both touched styling. |
| 5 | `adaptive_controls` | `bumpVolume`, `openAdvanced`, `setProgress`, `snapshot` | The Milestone B controls in one screen. Capture `compact-phone-landscape` and `tablet-landscape` — the two matrix rows with **no capture id** — and drive a **keyboard** row with `user_keyboard_input` (Down/Return), which closes `D-4`'s keyboard half. |

Reset between scenarios with `reset()`; it tears down and rebuilds the fixture.

## 3. What is being asked of you

One judgment, and it is the only genuinely human one in the packet:

**`P5` — do the adaptive results read well?** Review the stored captures per view row
(`D-1_..._compact-phone-portrait_rest`, `D-4_..._desktop-standard_rest`,
`B-BTN2_..._desktop-standard_roles`, `D-5_..._console-ten-foot_rest`) and say whether the
settings screen and the status column have acceptable readability, hierarchy and platform
feel at each profile, or list what to change. Nothing automated can answer this.

Everything else in §2 is mechanical: rows 2, 3 and 5 close `A-SV1`'s geometry, the two
missing captures, and `D-4`'s keyboard half. The hit-floor decision is already taken
(`HANDBACK.md` §4) — reverse it only if you disagree with the reasoning there.

## 4. Physical and human rows — never closed by this packet

These stay `PENDING_PHYSICAL` / `PENDING_HUMAN` under contract §3. Do **not** fill them
with emulator or headless results.

| ID | What it needs | Procedure |
|---|---|---|
| P1 | Physical touch | On a real phone: finger-target every control in the `adaptive_controls` scenario, pan the native `ScrollView` in `scroll_host` for momentum, and judge the Slider's drag feel. |
| P2 | Real gamepad | Physical controller: confirm `PreferredInput == Gamepad`, Button A contention, focus navigation, and `Adjust` at ten-foot distance. |
| P3 | Mobile OS keyboard | On a real phone: focus each text surface and record the occluded layout result (the device emulator does not summon the OS keyboard). |
| P4 | Floor-device performance | Dense fixtures on the supported low-end Android with MicroProfiler, against the versioned budget. |
| P5 | Human adaptive review | Readability, hierarchy and platform feel per profile — reviewable NOW from the stored captures (see §3). Note that `A-AL4` has no dense HUD yet, so that half of the judgment is not available. |

P5 is reviewable now for the settings surface; the dense-HUD half waits on `A-AL4`.

## 5. Rollback

Nothing was published, deployed, pushed, or committed, and no Git repository was
initialized. Every change is under `GameStudio/ui/LuauUI/`. To revert the stage, discard
that directory's working changes; `games/RascalRally/` was not touched (its 5 dirty files
pre-date this session — see `game-suite.txt`).
