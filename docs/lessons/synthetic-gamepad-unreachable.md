# Synthetic gamepad input cannot exist in Studio: three stacked gates

Observed live 2026-07-21 (input-paradigms defect trace, `02_playlist_table.rbxl`):

1. `VirtualInputManager:HandleGamepadConnect` / `HandleGamepadDisconnect` are
   **RobloxScript-capability-gated** — refused from Studio command bars, plugins,
   and MCP `execute_luau` in every VM ("lacking capability RobloxScript"). No
   virtual pad can be connected.
2. `VirtualInputManager:SendKeyEvent` (and the MCP `user_keyboard_input` tool)
   with gamepad KeyCodes (`ButtonA`, `DPadDown`, …) delivers events whose
   `UserInputType` is **Keyboard**, not `Gamepad1` — IAS KeyCode bindings still
   fire (which is why past binding drives worked), but `UserInputService.
   PreferredInput` flips toward **KeyboardAndMouse**, never Gamepad, and
   `GamepadEnabled` stays false.
3. A **physical** pad is frequently not forwarded by Studio on this development platform at all
   (`GamepadEnabled=false`, `GetConnectedGamepads()` empty) — documented
   DevForum bug class, compounded by the Controller-Emulator beta occupying the
   `Gamepad1` slot. Sourced:
   `docs/research/2026-07-21-preferredinput-gamepad-research.md`.

**Rule:** never design a check that needs `PreferredInput == Gamepad` (or any
true gamepad-class UIS fact) to pass inside Studio — it is unreachable
synthetically and unreliable physically. Prove gamepad *bindings* via KeyCode
injection or Scriptable `InputBinding:Fire()`; prove gamepad *affordance
derivation* headlessly through env facts (ADR-0015 `interactionClasses` exists
exactly so affordances do not hang off the unreachable engine fact); and leave
the real-pad flip to the standing `physical-device-confirmation` rider (retail
client / console).

Corollary verified the same session: `GetPropertyChangedSignal("PreferredInput")`
DOES fire and propagate live for the flips synthetic input can produce
(Touch ↔ KeyboardAndMouse), so the subscription layer is provable without a pad.
