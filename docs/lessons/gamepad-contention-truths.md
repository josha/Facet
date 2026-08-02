# Gamepad ButtonA contention truths (ui_todo.md §3, live-probe-verified 2026-07-20)

Three hard Roblox-platform facts about gamepad `ButtonA` in a UI place, probed
against a live gamepad on 2026-07-20 (`ui_todo.md` §3;
`artifacts/input-adaptation-audit/matrix.md` §5). Each will silently kill gamepad
Activate if you do not know it. This file is the compact durable version plus a
map of where each truth is now encoded so a future consumer cannot re-hit it.

## The three truths

1. **`jumpAction` eats `ButtonA` unconditionally.** The legacy avatar control
   scripts bind gamepad `ButtonA` to `jumpAction` at `ContextActionService`
   priority 2000 **unconditionally** — even with `Players.CharacterAutoLoads =
   false` and no character — and consume it (`gameProcessedEvent == true`), so
   the Input Action System's Activate never fires. D-pad and thumbsticks pass
   through, which masks it until a gamepad user presses A on a button.

2. **`Workspace.PlayerScriptsUseInputActionSystem` is Properties-panel-only.**
   The flag that puts avatar input onto IAS (so it joins arbitration instead of
   contending) is **not** script- or rojo-reflectable — code can neither read nor
   set it (re-verified 2026-07-20). A human must toggle it in Studio. Best a
   script can do is probe the *symptom* (a `jumpAction` binding present) to warn.

3. **`GuiService.CoreGuiNavigationEnabled` re-enables itself if scripted off.**
   CoreScripts reassert it, so a scripted-off "fix" does not hold — and it is not
   the `ButtonA` eater anyway (`jumpAction`, truth 1, is). Do not build on it.

## The two remedies (they are NOT the same)

- **UI-only place** (menu shell / lobby / the LuauUI gallery — no player-driven
  avatar): disable the control scripts. `gamepad_contention.disableLegacyControls()`
  does `PlayerModule:GetControls():Disable()`, fallback
  `CAS:UnbindAction("jumpAction")`.
- **Real game** (player is walking/driving/aiming): **never** disable avatar
  input. Set `PlayerScriptsUseInputActionSystem = true` (truth 2) so avatar input
  joins IAS, then let UI-vs-gameplay contention resolve through InputContext
  priority + Sink — a focus-aware first-responder model (Apple responder-chain
  analog): an *engaged* LuauUI surface (modal, or a screen the player entered)
  sinks its context above the avatar contexts; a passive HUD binds nothing
  gameplay-contended. The framework-level engagement model is being designed
  under **ADR-0014 (in progress)** — do not hand-roll one ahead of it.

## Where each truth is now encoded

| Truth | Encoded in |
|---|---|
| 1 (jumpAction eats ButtonA) | `src/client/gamepad_contention.luau` — `disableLegacyControls()` (UI-only fix) + `describeContention()`; the gallery bootstrap `examples/gallery/client/init.client.luau` routes through it; guide `docs/guide/07-input.md` §7.2 Truth 1 |
| 2 (flag is Properties-panel-only) | `gamepad_contention.legacyStackActive()` (behavioral symptom probe, since the flag is unreadable) + module header; guide §7.2 Truth 2 + "the real-game path" (flag → IAS arbitration → first-responder / ADR-0014) |
| 3 (CoreGuiNavigationEnabled fights back) | `gamepad_contention` header + `describeContention()` (recorded as a known non-fix; the module deliberately never touches it); guide §7.2 Truth 3 |

## What is proven vs. what is riderd

The headless spec (`tests/gamepad_contention.spec.luau`) proves the module is
require-safe and its engine calls are `pcall`-guarded — **not** that disabling
the controls actually frees `ButtonA` end-to-end. Virtual/injected input cannot
press a real Cross/A button and observe Activate fire; that rests on the
2026-07-20 live-gamepad probe and stays the standing `physical-device-confirmation`
rider (non-release-blocking `FAIL_ENVIRONMENT`, `tools/lune/gate_manifest.luau`).

See also `docs/lessons/gamepad-buttona-jumpaction.md` (the original truth-1-only
note) and `docs/guide/07-input.md` for the full developer-facing story.
