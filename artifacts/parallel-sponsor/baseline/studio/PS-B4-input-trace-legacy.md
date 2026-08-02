# PS-B4 — legacy input trace (baseline, 2026-07-30)

**Session:** bench `TrackLayout=debug`, Play Solo, sponsor role via
`SponsorCmd:FireServer("role","sponsor")`. No device emulator (see instrument
limits). Viewport 907×1044 (portrait split). Suite state: RR 2425 green.

## Trace: arm → tap-commit (the ratified tap flow)

1. Injected click on `HandDock.CardSlot1` ("Headwind") → **armed**: per-row aim
   `Ring` elements appeared on eligible racer rows (capture
   `PS-B4-card-armed-legacy-desktop-pane-portrait.png`); no command sent.
2. Injected click on the P2 row (Wrenchy / AIKart_4) → **exactly one** server
   receipt, logged by the session hook on `SponsorCmd.OnServerEvent`:

   ```
   [PSB4TRACE] t=1558.658 plr=JoshSedai verb=play a=headwind b=AIKart_4 c=nil
   ```

   One intent → one authoritative command. This is the duplicate-command
   baseline the LuauUI presenter is compared against (PS-L6).

Command shape frozen: `SponsorCmd:FireServer("play", <cardId>, <kartName>)`.
Role command shape: `("role", "sponsor"|"racer")`.

## Instrument limits measured this session (binding for later parity rows)

- **The Studio Device Emulator swallows ALL `user_mouse_input` injection**:
  with any emulated device active, neither instance-path nor x/y injected
  events reach the client (0 `InputBegan`, 0 `Activated`). Interactive drives
  must run with the emulator OFF; emulated rows are geometry/state evidence.
- With the emulator off, **instance-path injection fires `GuiButton.Activated`
  (GUI path) but never global `UserInputService` streams**; raw x/y moves are
  dead (`GetMouseLocation` never tracks injected moves). Consequences:
  - tap/click flows are drivable and are labeled downstream GUI-path evidence;
  - the legacy **pointer drag→promotion path cannot be driven by injection**
    (SponsorGesture's press→drag promotion needs the global pointer stream —
    verified: no ghost, 0 samples). Pointer-drag feel/trace rows stay with the
    physical-device pass (PS-G4/G5) and the M12 device sittings as their bar.

## Pre-existing environment notes (not defects introduced by this stage)

- Server warning under the bench, repeatable: `Attribute total payload exceeds
  1024 bytes` from `SponsorRound` `publishRollCall` (line 514) and
  `publishPromotions` (line 632).
- CoreGui `Settings.Pages.Players:1931 layoutMuteAll` error (Roblox CoreGui,
  unrelated to game code).
- `Infinite yield possible on PlayerModule:WaitForChild("InputContexts")`
  (known engine-module noise).
