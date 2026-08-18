# Input contention truths (ui_todo.md §3, live-probe-verified 2026-07-20 and 2026-08-15)

Hard Roblox-platform facts about keys Roblox's own scripts hold *outside* the
Input Action System, where no `InputContext` can reach them. Truths 1–3 were
probed against a live gamepad on 2026-07-20 (`ui_todo.md` §3;
`artifacts/input-adaptation-audit/matrix.md` §5); truth 4 and the reflection
finding in truth 2 were re-probed live on 2026-08-15. Each will silently kill an
input if you do not know it — gamepad Activate for truth 1, horizontal navigation
for truth 4. This file is the compact durable version plus a map of where each
truth is now encoded so a future consumer cannot re-hit it.

**All of it collapses to one action:** the embedding experience ticks
`Workspace.PlayerScriptsUseInputActionSystem` (truth 2). That is a Facet
requirement, not a suggestion, because no priority number is an alternative.

## The truths

1. **`jumpAction` eats `ButtonA` unconditionally.** The legacy avatar control
   scripts bind gamepad `ButtonA` to `jumpAction` at `ContextActionService`
   priority 2000 **unconditionally** — even with `Players.CharacterAutoLoads =
   false` and no character — and consume it (`gameProcessedEvent == true`), so
   the Input Action System's Activate never fires. D-pad and thumbsticks pass
   through, which masks it until a gamepad user presses A on a button.

2. **`Workspace.PlayerScriptsUseInputActionSystem` is Properties-panel-only —
   and it is a Facet REQUIREMENT, not a tuning knob** (director, 2026-08-15).
   The flag that puts Roblox's own player scripts onto IAS (so they join
   arbitration instead of contending) is **not** script- or rojo-reflectable —
   code can neither read nor set it. A human must toggle it in Studio. Best a
   script can do is probe the *symptom* to warn.

   **It is not-scriptable, which is NOT the same as absent — re-probed
   0.734.0.7340915, 2026-08-15.** A plain read errors `is not a valid member of
   Workspace`, which reads like "this build lacks it". It does not:
   `GetPropertyChangedSignal` answers **`is not a scriptable property`**, while a
   made-up name answers **`is not a valid property name`** — run that negative
   control (`capability-probes-must-be-tri-state`). The property is in the
   reflection database with scriptability off, the same class as
   `StarterPlayer.CreateDefaultPlayerModule` and `Workspace.SignalBehavior`. So
   this is **not a rollout window a newer build closes**: no Facet version on any
   build will read it, and every diagnostic here stays behavioural forever.

   **Why "requirement" and not "recommended": no priority number is an
   alternative.** CAS priority and `InputContext.Priority` are not one
   arbitration space — a CAS sink at priority 100 beat an `InputContext` at
   10000 (`the-camera-still-owns-the-arrow-keys`). With the flag off there is no
   in-framework remedy at all, so the loss is silent and total.

3. **`GuiService.CoreGuiNavigationEnabled` re-enables itself if scripted off.**
   CoreScripts reassert it, so a scripted-off "fix" does not hold — and it is not
   the `ButtonA` eater anyway (`jumpAction`, truth 1, is). Do not build on it.

4. **The camera holds the arrows, and it is a SEPARATE binding from truth 1.**
   `RbxCameraKeypress` binds `Left`/`Right`/`I`/`O` at CAS priority 2000 and
   sinks them, so horizontal focus navigation and a Table's selected-column
   resize never receive a keypress. Measured live 2026-08-15, it held the arrows
   in a session where `jumpAction` was **not bound at all** (the controls module
   had already been disabled) — so `legacyStackActive()` answered `false` while
   the arrows were dead. Jump and camera come from different CoreScripts; probe
   them separately with `gamepad_contention.cameraKeysContended()`. Same fix as
   truth 2, and only that fix.

## The two remedies (they are NOT the same)

- **UI-only place** (menu shell / lobby / the Facet gallery — no player-driven
  avatar): disable the control scripts. `gamepad_contention.disableLegacyControls()`
  does `PlayerModule:GetControls():Disable()`, fallback
  `CAS:UnbindAction("jumpAction")`.
- **Real game** (player is walking/driving/aiming): **never** disable avatar
  input. Set `PlayerScriptsUseInputActionSystem = true` (truth 2) so avatar input
  joins IAS, then let UI-vs-gameplay contention resolve through InputContext
  priority + Sink — a focus-aware first-responder model (Apple responder-chain
  analog): an *engaged* Facet surface (modal, or a screen the player entered)
  sinks its context above the avatar contexts; a passive HUD binds nothing
  gameplay-contended. The framework-level engagement model is being designed
  under **ADR-0014 (in progress)** — do not hand-roll one ahead of it.

## Where each truth is now encoded

| Truth | Encoded in |
|---|---|
| 1 (jumpAction eats ButtonA) | `src/client/gamepad_contention.luau` — `disableLegacyControls()` (UI-only fix) + `describeContention()`; the gallery bootstrap `examples/gallery/client/init.client.luau` routes through it; guide `docs/guide/07-input.md` §7.2 Truth 1 |
| 2 (flag is Properties-panel-only) | `gamepad_contention.legacyStackActive()` (behavioral symptom probe, since the flag is unreadable) + module header; guide §7.2 Truth 2 + "the real-game path" (flag → IAS arbitration → first-responder / ADR-0014) |
| 3 (CoreGuiNavigationEnabled fights back) | `gamepad_contention` header + `describeContention()` (recorded as a known non-fix; the module deliberately never touches it); guide §7.2 Truth 3 |
| 4 (the camera holds the arrows) | `gamepad_contention.cameraKeysContended()` (reads `GetAllBoundActionInfo()` for Left/Right/Up/Down — a direct read, not an inference) + `describeContention()` truth 6; guide §7.4 "Left and Right arrow do nothing"; api.md `## Input` requirement block; `the-camera-still-owns-the-arrow-keys` |

## What is proven vs. what is riderd

The headless spec (`tests/gamepad_contention.spec.luau`) proves the module is
require-safe and its engine calls are `pcall`-guarded — **not** that disabling
the controls actually frees `ButtonA` end-to-end. Virtual/injected input cannot
press a real Cross/A button and observe Activate fire; that rests on the
2026-07-20 live-gamepad probe and stays the standing `physical-device-confirmation`
rider (non-release-blocking `FAIL_ENVIRONMENT`, `tools/lune/gate_manifest.luau`).

See also `docs/lessons/gamepad-buttona-jumpaction.md` (the original truth-1-only
note) and `docs/guide/07-input.md` for the full developer-facing story.
