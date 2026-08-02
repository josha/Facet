# ADR-0015 — Interaction classes: affordances derive from the live capability set + preferredInput, never preferredInput alone

Date: 2026-07-21 · Status: **Accepted** · Spec: input-paradigms expansion (prompt.md "Expansion: input paradigms"), design §8/§9 · Research: [`2026-07-21-preferredinput-gamepad-research.md`](../research/2026-07-21-preferredinput-gamepad-research.md), [`2026-07-21-swiftui-affordance-research.md`](../research/2026-07-21-swiftui-affordance-research.md)

## Context

**The live defect (director, 2026-07-21).** On a Mac running Studio with a physical
gamepad, gallery example 02 showed no Edit button, though the auto Edit/Done machinery
was green engine-free. The live trace (Studio MCP, same day) verified every layer:
`UserInputService:GetPropertyChangedSignal("PreferredInput")` fires, `roblox_env.bind`
pushes the fact, the Table memo re-evaluates, the `When` mounts/unmounts, and the
adapter renders — both directions. The failing layer is the **engine fact itself**:
commissioned platform research established that Studio on macOS frequently does not
forward physical HID gamepads at all (`GamepadEnabled == false`, `GetConnectedGamepads()`
empty — documented DevForum bug class, compounded by the Controller-Emulator occupying
the `Gamepad1` slot), so `PreferredInput` *could not* report `Gamepad` in that session.
Synthetically unreachable: `VirtualInputManager:HandleGamepadConnect` is
RobloxScript-capability-gated, and `SendKeyEvent` with gamepad KeyCodes arrives as
`UserInputType.Keyboard` (both verified live).

**The design defect underneath.** Even on healthy hardware, `Enum.PreferredInput` is a
single value while real devices are multi-modal: a handheld has touch + gamepad live at
once; docking adds mouse/keyboard mid-session; a desktop with a pad connected is both a
pointer and a gamepad machine. Any affordance keyed on `preferredInput` alone
(`table.luau` pre-fix: `preferredInput ~= "KeyboardAndMouse"`) disappears for every
class the single value does not name — exactly the SwiftUI lesson that multiple input
modes coexist and arrive mid-session (research §10).

## Decision

1. **New derived environment key `interactionClasses`** (`src/env/environment.luau`,
   engine-free, zero consumer wiring): a memo over the `capabilities` +
   `preferredInput` fact keys returning
   `{ pointer, touch, gamepad, keyboard: boolean, primary: "pointer"|"touch"|"gamepad" }`.
   - A class is **live** when its capability fact is true.
   - `preferredInput` names the **primary** class; the primary is forced live even when
     its capability fact disagrees (a lagging adapter must never yield a primary outside
     the set).
   - Garbage capability facts clamp to defaults (same policy as every derived key).
2. **Affordance rule.** Controls choose *structural affordances* from the live class
   set (any live class must get its idiom), and use `primary` only for emphasis/UX
   priority (hints, which idiom leads). The Table's auto Edit/Done toggle now shows when
   `touch or gamepad` is live — not when the preference happens to say so.
3. **Adapter hardening** (`src/client/roblox_env.luau`): capability facts move
   independently of the preference. Added subscriptions: `GamepadConnected` /
   `GamepadDisconnected`, `GetPropertyChangedSignal` on the four `*Enabled` properties,
   and a **sticky `sawGamepadInput`** fallback — any `Gamepad*` `UserInputType` seen via
   `LastInputTypeChanged` proves the class is live even when detection fails
   (`GamepadEnabled=false` with a working pad is the documented engine failure class).

## Consequences

- The director's repro is fixed on every path the engine can report at all: pad
  detected (capability fact), pad producing input while undetected (sticky fallback),
  or preference correctly flipped (primary). The one unfixable path — Studio/macOS not
  forwarding the pad AND no gamepad input reaching the engine — is an engine limitation
  upstream of Luau; physical-device confirmation remains the standing pending release
  item (retail client / console).
- Regression tests at the failing layer (`tests/table.spec.luau`): gamepad capability
  live under a KeyboardAndMouse preference shows the toggle (and disconnect hides it);
  touch capability live under KeyboardAndMouse shows it (hybrid handheld). Suite
  491 → 493 at this ADR; the hybrid/hot-switch work packages extend the model to every
  control (per-class affordance proofs in the conformance registry).
- `preferredBinding`/`inputHint` continue to read `preferredInput` (emphasis is exactly
  what the preference is for, per the platform research: it is the doc-endorsed
  presentation signal). Structural affordances no longer do.

## Alternatives considered

- **Keying affordances off `LastInputTypeChanged` heuristics** — rejected: the platform
  research confirms `PreferredInput` is the doc-endorsed successor to hand-rolled
  last-input heuristics for *presentation*; the failure here is structural gating, not
  the preference signal itself. Last-input is used only as a sticky liveness proof.
- **Always showing the Edit toggle** — rejected: a pure mouse world genuinely never
  needs it (wheel scrolls, rows drag directly — SwiftUI/macOS idiom, research §1/§8),
  and the env-less fallback (`spec.env == nil` → always show) already covers consumers
  who cannot know better.
