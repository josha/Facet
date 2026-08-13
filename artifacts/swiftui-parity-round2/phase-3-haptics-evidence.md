# `UI.sensoryFeedback` + the haptics adapter — evidence ledger

Stage: SwiftUI parity round 2, Phase 3 §3.3
(`docs/plans/swiftui-parity-round2.md`). Engine facts:
[`docs/research/2026-08-12-haptics-engine-facts.md`](../../docs/research/2026-08-12-haptics-engine-facts.md).
Date: 2026-08-13.

**The split this file exists for.** Everything about *what the framework says* is
headless-proved. Nothing about *what a player feels* is, and this machine cannot
close that: Roblox's full-release announcement lists "All game controllers
connected to MacOS 15+" as unsupported, so no Studio run here can ever be
positive device evidence.

## Shipped

| Piece | Where |
|---|---|
| `UI.sensoryFeedback(bp, { trigger, event })` | `src/blueprint.luau`; contract + taxonomy in `src/present/feedback.luau`; wiring in `src/mount.luau` (`opts.feedback` sink), fed by `src/present/presenter.luau` |
| The opt-in, **default-off** adapter | `src/client/haptics.luau` (blessed client entry point; `tools/lune/check_boundary`) |
| Specs | `tests/sensory_feedback.spec.luau` (14), `tests/haptics.spec.luau` (43) |
| Docs | `docs/reference/api.md` → `### sensoryFeedback`, `#### client.haptics`; surface ledger rows |

## The mapping, total over the closed twelve

`false` = deliberately silent, written out explicitly so a thirteenth verb
surfaces as a visible gap (`haptics.unmappedVerbs()`, asserted empty).

| Verb | Route | `HapticEffectType` | Why |
|---|---|---|---|
| `activate` | **property** — `GuiButton.PressHapticEffect` | `UIClick` | the ENGINE fires it; the framework assigns a reference and never calls `Play()`, so "LuauUI plays nothing" stays literally true |
| `select` | bus | `UIClick` | a discrete choice landing |
| `adjust` | bus, **rate-limited** (60 ms default) | `UIHover` | per-tick from sliders/steppers; unthrottled it is a buzzsaw and a breach of the documented "<100 simultaneous effects" budget |
| `pickup` | bus | `UIClick` | acquisition is a discrete moment |
| `commit` | bus | `UIClick` | the drop took |
| `reject` | bus | `UINotification` | a refusal must not feel like a commit |
| `land` | bus | `UIClick` | the payload reached its resolved drop |
| `celebrate` | bus | `UINotification` | the preset documented as "draw the player's attention" |
| `arrive` | — | *none* | fires on every chase settle; a haptic there is per-frame noise |
| `cancel` | — | *none* | the ABSENCE of feedback is the signal for "nothing happened" |
| `dismiss` | — | *none* | not player-caused |
| `supersede` | — | *none* | not player-caused — a replacement nobody asked for |

Pool: one effect per mapped bus verb (7) plus one for the press property (8
maximum), never constructed per fire.

## Headless-proved (57 cases, all mutation-proved)

- default-off produces **zero constructions and zero plays**, and no device
  listener and no platform claim;
- the map is **total** over `feedback.TYPES`, invents no verb, and its five
  explicit silences are the five decided;
- `adjust` coalesces a 20-tick storm to one play under a scripted clock, and the
  coalescing **drops** (nothing is replayed late as a phantom);
- the probe answers **`unknown`** for touch and for the pre-first-gamepad state,
  `unsupported` only when a connected pad answers false, and re-probes on
  `GamepadConnected` / `GamepadDisconnected` / `LastInputTypeChanged`;
- enum resolution never throws and **never falls back to `Custom`** — an
  unresolvable name constructs nothing at all;
- an uncreatable class is `absent` and any other refusal is `blocked`, with the
  engine's own error text kept;
- the property route assigns `PressHapticEffect` (shared, one per surface),
  covers late `DescendantAdded` buttons, clears on disable and on detach, leaves
  `HoverHapticEffect` alone, and **never calls `Play()`** — pinned structurally
  by a source check that there is exactly one `:Play()` call site in the module;
- no haptic symbol (`HapticEffect`, `HapticService`, `SetMotor`,
  `VibrationMotor`) and no require of the adapter exists anywhere in `src/`
  outside `src/client/`; `src/present` and `src/layout` are separately asserted
  clean; `src/init.luau` does not export it.

## Studio canary — 2026-08-13, Edit, `LuauUI-Showcase.rbxl` (macOS)

Proves **API shape and "never throws"** only. Every value below is a live read.

| Probe | Result |
|---|---|
| `Instance.new("HapticEffect")` | ok |
| the six `Enum.HapticEffectType` names resolve | all six ok |
| `Enum.HapticEffectType["UISelection"]` | **throws on index** (not nil) — the guessed name from the game side is not a member, and an unguarded lookup would crash. The adapter resolves inside a `pcall` for exactly this |
| `effect.Type = …`, `effect.Parent = workspace`, `Play()`, `Stop()` | all ok |
| `TextButton.PressHapticEffect = effect` | ok; reads back as `HapticEffect`; clears to nil |
| `TextButton.HoverHapticEffect` (untouched) | nil |
| `UserInputService.IsHapticSupported` | **not a valid member** (errors on index) — confirms there is no capability API |
| `UserInputService:GetConnectedGamepads()` | `0` pads |
| `HapticService:IsVibrationSupported(Gamepad1)` with **0 pads connected** | **`false`** |

That last row is the lesson made live: the only probe on the platform reported a
flat `false` on a machine with no gamepad attached at all. A boolean adapter
would have published "this device does not support haptics". This one publishes
`unknown`.

## PENDING_PHYSICAL — three rows only a device closes

| Row | Claim owed | Why it cannot close here |
|---|---|---|
| `haptics-gamepad-felt` | a mapped verb produces a **perceptible** rumble on a PlayStation/Xbox/Quest pad | Roblox documents "All game controllers connected to MacOS 15+" as unsupported; this dev machine is darwin. A silent run here is not evidence that haptics do not work |
| `haptics-phone-felt` | the same on a haptic-capable iOS/Android phone | no device in the loop; the docs say only "most" iPhone/Pixel/Galaxy devices have haptics, which is also why touch is permanently `unknown` rather than `supported` |
| `haptics-player-preference-honored` | the player's own Roblox haptics setting silences/scales what this adapter plays | `UserGameSettings.HapticStrength` is `Hidden, NotReplicated, RobloxScriptSecurity` on **both** read and write — game code cannot read the setting, so the question is unanswerable from inside the process. Whether `HapticEffect` is scaled by it at all is undocumented |

None of these is claimed anywhere in the code, the docs or the tests. The
adapter's own `support()` never returns `supported` on the strength of anything
in this file.
