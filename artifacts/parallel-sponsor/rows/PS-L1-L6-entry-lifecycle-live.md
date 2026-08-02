# PS-L1..L6 — layer L1 (entry + lifecycle) live Studio evidence

**Date:** 2026-07-30 · Play Solo, bench `TrackLayout=debug`,
`UseLuauUISponsor=true`, `SponsorScenarioRig=true`. Suite at session: game
**2545** / LuauUI **2597**, stylua clean, 11/11 legacy checksums OK. Export
instrument: `workspace.LuauUISponsorDevReport:Invoke()` (JSON string; dev-only
BindableFunction, exists only on the production construction path in Studio,
removed on destroy). Flags + `TrackLayout=firstSmile` restored after.

## Proven live this session

- **PS-L1 (boot):** fresh join → `rolePick.up=true`, `modals=1, depth=2`,
  initial focus `/RolePick/Card/Primary/RaceNow` (FocusRingFloat on it),
  `commands.total=0`, base HUD passive, `pose.maximized=true` seeded. Capture:
  `PS-L2-rolepick-modal.png`.
- **PS-L2 (role modal):** keyboard Navigate (Down) moved focus to
  `/Secondary/CauseChaos` with the modal held and zero commands; Backspace did
  not dismiss (no keyboard dismissal path); Return on the focused CTA →
  **modal dismissed, exactly one `("role","sponsor")`** — client counters
  `{role=1, total=1}` == server receipts `{role=1, play=0}`; server confirmed
  `SponsorRole=sponsor`; `isActive=true`; responder → `engaged`.
- **PS-L3 (phase arc):** rig held grace→results→racing; mid-hold client
  `phase=="results"` while held; after release `phase=="racing"`;
  `surfaces.depth` stayed 1 throughout — no surface leaked a boundary;
  `modals=0` after the arc.
- **PS-L4 (responder):** `GuiService.SelectedObject == nil` while engaged
  (hard platform rule); passive→engaged edge proven via the pick flow.
- **PS-L6 (one command per intent):** server-side receipt count equals the
  presenter counter for every verb this layer owns; only one presenter
  mounted (flag-state exclusivity proven earlier in
  `PS-L6-selector-live-proof.md`).

## Instrument limits hit (recorded, drive the pending rows)

- `VirtualInput` refuses `ButtonB` ("permanently bound to a CoreGUI core
  action") and silently drops `ButtonY` — gamepad Cancel-no-op and TogglePose
  live drives are **physical-gamepad rows** (headless coverage: 6 cancelPolicy
  cases + pose specs; PS-G5).
- Arbitrary-point outside-tap is not injectable (raw x/y dead) — outside-tap
  resign stays with the physical/touch pass (PS-G4).
- `execute_luau` cannot reach the presenter module registry (isolated
  environments) — hence the BindableFunction export, same convention as the
  scenario rig. Recorded for every later layer.

## Layer L1 headless closure (from the implementing package, verified in suite)

Ten full lifetimes churn = zero residue + exactly one command each;
mashed-CTA cannot double-send; bridge total/dispose; 25-cycle registry-neutral
churn; `cancelPolicy="none"` framework option (LuauUI tests + api.md).
