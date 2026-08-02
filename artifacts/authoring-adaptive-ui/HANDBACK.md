# authoring-adaptive-ui — handback

**Date:** 2026-07-24 · **Gate:** `authoring-adaptive-ui` (roadmap Step 3)
**Status:** 16 PASS · 1 FAIL_ENVIRONMENT · 2 PENDING → gate **PENDING**

Milestones 0, A and B are delivered with named exceptions. The live five-view Studio
matrix and the required fresh-context review are closed. Per contract §10:
**automation complete with named exceptions, release evidence pending.**

`SUMMARY.md` is the short version. This file is what a person needs to resume.

---

## 1. What is genuinely done

Milestone 0 (strict authoring), Milestone A (`ScrollView` axes + shared keep-visible,
`AdaptiveStack`, `ViewThatFits`, `LuauUI.adaptive`, `Grid` fill, `Spacer` default, seven
layout modifiers, `Divider`), and Milestone B (`Button` complete, `Stepper`, `Slider`,
`ProgressView`, `Label`, `Picker`, `DisclosureGroup`, PopupButton floor).

Suite **672 → 898**. Both drift checkers green. 11/11 prior gates PASS. Game suite 2404
green with zero game-code edits. Fresh-context review run: `ACCEPT_WITH_FINDINGS`,
21 findings, all fixed or corrected — see `verifier-phase-gate.json`.

Eleven defects were found along the way, nine of them shipping. They are listed in
`SUMMARY.md`; the three the fresh-context verifier found are the most instructive,
because each sat inside a row already marked PASS and none was visible to the suite.

---

## 2. What is NOT done

### `A-SV1` live geometry — FAIL_ENVIRONMENT, needs a stable Studio window

Absolute geometry for the scroll hosts, plus a wheel-injection row proving
engine-driven `CanvasPosition` change and descendant clipping. Driven twice; both times
the Studio window left the window server mid-session and the play camera collapsed to
`1×1`, so the widths were discarded. Step results reproduced identically and the canvas
extents (viewport-independent) are stored — including the horizontal region reporting a
928 px **wide** canvas, which is the A-SV1 fix.

**To close:** `open -a "RobloxStudio"` (this is the recovery the lesson was missing —
`activate` and `set frontmost` do not work), confirm
`workspace.CurrentCamera.ViewportSize > 1,1`, set `LuauUI_Scenario = "scroll_host"`,
Play, run the four `keepVisible*`/`readOffsets` steps, then inject a wheel over the
vertical list. Do it in one pass without switching away — this window did not survive
being backgrounded.

### Three plan items, not started

- **`B-DSP3` second half** — PopupButton's adaptive popup-vs-inline-vs-sheet
  presentation. Its target-floor half is done (it comes free from `B-BTN3`). Switching
  presentation means moving proven transient-surface machinery — `outsideDismiss`,
  `transientScope`, the synthesized catcher — behind a switch, which deserves its own
  slice with live evidence. `newPicker` supplies the adapting alternative meanwhile.
- **`A-SV2`** — Table/VirtualList still carry hand-written scroll behaviour.
  `controller.scrollToVisible` is the substrate they should consume. The migration must
  prove that reparenting into the native host preserves style rules, `Path2D` children,
  drag detectors and logical identity.
- **`A-LV4` remainder** — overlays, 16:9 media, and the enlarged-text compression
  result are unfixtured. There is no `layout_vocabulary` gallery fixture (the ledger row
  named one that never existed; corrected).

### Evidence gaps inside otherwise-passing rows

- **`A-AL4` is PARTIAL.** The write-once half is proven, but its declared
  `adaptive_settings` + `adaptive_hud` fixtures do not exist (one `adaptive_controls`
  scenario substitutes for both, and its "Status" column is not a dense HUD), and the
  preferred-text and hybrid-input axes were not swept.
- **`D-2` and `D-3` have no capture** — 3 capture ids exist across the 5 rows, and
  `D-5`'s is cropped by the physical window.
- **`D-4`'s keyboard half was not driven.** `VirtualInput` exposes no send methods at
  this security level, but this repository's own lessons document a working MCP
  `user_keyboard_input` path that was not attempted. Every keyboard claim in
  `B-BTN4`/`B-VAL3`/`B-DSP2` is therefore E1 only. **This is the cheapest remaining win.**
- Several Milestone B rows are `PASS_AUTOMATED (headless)` and say what live trace is
  still owed. The live matrix covers the adaptive rows, the role paint, the hit floor and
  the Stepper's pointer path — not a per-input live trace for every control.

### `P1`–`P5` — physical and human

Never closable by emulator or headless evidence. See `review-packet.md`.

---

## 3. Instrument facts worth knowing before you start

1. **`open -a "RobloxStudio"` is the 1×1 recovery.** `activate` / `set frontmost` /
   Play restarts do not restore a window the window server is not listing.
2. **`StudioDeviceSimulatorService`** exposes only `GetDeviceListAsync`,
   `GetDeviceInfoAsync` and `ConfigurationChanged` from `execute_luau`. Every setter is
   plugin-security. Resolve presets through the API; drive their facts through the
   verification surface's `setEnv` seam.
3. **`VirtualInput` is unusable** from `execute_luau` — created successfully, no send
   methods. Use the MCP's `user_mouse_input` / `user_keyboard_input`.

---

## 4. The one decision already taken (recorded, reversible)

The hit-target floor is enforced in **hit geometry**, not by growing the visual rect,
because flooring painted size would silently rewrite shipped design (a 22 px icon button
would double). The trade-off — two sub-floor controls closer than 44 px get overlapping
hit areas, with the control's own rect winning — is documented in `api.md`. Rationale in
`b-btn-button.json`. Reverse it if you would rather have one geometry than two.
