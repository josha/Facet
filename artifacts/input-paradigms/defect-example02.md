# Example-02 gamepad defect — root cause + fix disposition (2026-07-21)

Repro (director, physical gamepad, macOS Studio): gallery example 02 showed **no
Edit button** although the auto Edit/Done machinery was green engine-free.

## Live trace (Studio MCP, 02_playlist_table.rbxl, this session)

Layer-by-layer, evidence gathered before any fix:

| Layer | Check | Result |
|---|---|---|
| Place staleness | in-memory `table.luau`/`roblox_env.luau` byte sizes vs disk (50584 / 3127) | **match — place NOT stale** |
| Engine fact | `UserInputService.PreferredInput` at play start | `Touch` (Studio device emulation live; `caps = {kb, mouse, touch}`) |
| Fact → env → render | EditToggle node under `Touch` | **present + visible** (`/Playlist/Tracks/ToggleWhen/then/EditToggle`) |
| Change signal | `GetPropertyChangedSignal("PreferredInput")` on synthetic input | **fires** (count 1; `Touch → KeyboardAndMouse`) |
| Full chain reverse | EditToggle after the flip to KeyboardAndMouse | **unmounted** — engine→env→memo→When→render live in both directions |
| Synthetic gamepad | `VirtualInputManager:HandleGamepadConnect` | **refused** — `lacking capability RobloxScript` |
| Synthetic gamepad | MCP key events with gamepad KeyCodes (`DPadDown`, `ButtonA`) | arrive as `UserInputType.Keyboard` — cannot flip PreferredInput to Gamepad |

Conclusion: every LuauUI layer is live and correct; the failing layer is the
**engine fact** — and the reliance on it alone.

## Root cause (two layers)

1. **Engine layer (documented platform limitation, not fixable from Luau).**
   Studio on macOS frequently does not forward physical HID gamepads
   (`GamepadEnabled=false`, `GetConnectedGamepads()` empty; DevForum bug class
   2023–2025, compounded by the Controller-Emulator occupying `Gamepad1`), so
   `PreferredInput` could not report `Gamepad` in the director's session.
   Sourced: `docs/research/2026-07-21-preferredinput-gamepad-research.md`.
2. **Design layer (LuauUI, fixed here).** The affordance was keyed on
   `preferredInput ~= "KeyboardAndMouse"` ALONE (`src/controls/table.luau`),
   with the env `capabilities` fact consumed by nothing. Any session where the
   single preference value lags or cannot flip loses the affordance for every
   other live class — hybrid devices structurally included.

## Fix (ADR-0015)

- `src/env/environment.luau`: derived `interactionClasses` key — live class set
  from `capabilities` + `preferredInput` (preferred forced live; garbage facts
  clamp).
- `src/controls/table.luau`: auto Edit/Done toggle shows when `touch or
  gamepad` is live, never from the preference alone.
- `src/client/roblox_env.luau`: capability facts now update independently of
  the preference — `GamepadConnected/Disconnected`, `*Enabled` change signals,
  and a sticky `sawGamepadInput` fallback from `LastInputTypeChanged` (any
  `Gamepad*` input proves the class live even when detection fails).

## Regression tests (at the failing layer, red-first)

`tests/table.spec.luau`:
- "auto Edit/Done toggle: shown when a gamepad capability is live even though preferredInput stays KeyboardAndMouse" (+ disconnect hides it again)
- "auto Edit/Done toggle: a live touch capability shows it under a KeyboardAndMouse preferredInput (hybrid handheld)"

Both failed against the pre-fix code (2 failed / 491 passed), suite green after
(493 passed).

## Studio drive (this session)

- Pre-fix chain drive: PASS both directions (table above).
- Post-fix drive: the three changed modules were patched into the open place
  (assert-guarded source replacement), place boots clean, EditToggle present
  under Touch emulation, no new console output.
- **Rider (recoverable, retry at phase-gate drive):** the post-fix live
  differential — toggle PERSISTING through a `Touch → KeyboardAndMouse` flip
  while the touch capability stays live — could not be completed this pass: the
  Studio window entered a degraded state mid-session (camera viewport 1×1,
  synthetic input no longer landing; user away from the machine). Headless
  regression covers the same seam; the live flip is re-driven with the final
  phase-gate Studio pass.

## Pending release item (physical-only)

A real `PreferredInput == Gamepad` flip from a physical pad is not exercisable
in this environment (engine gates + Studio/macOS forwarding). Confirm on the
retail client / console — folded into the standing
`physical-device-confirmation` rider.
