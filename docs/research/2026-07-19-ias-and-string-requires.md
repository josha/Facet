# Platform research: Input Action System + require-by-string (2026-07-19)

Opus verifier research; citations inline. Feeds the Phase 0 input-action and engine-fidelity spikes.

## Require-by-string in the engine — GA, vendor strategy safe

- `require("./X")`, `"../X"`, `"@self/X")` work for ModuleScripts in the DataModel instance tree, in live/published experiences, no beta flag (devforum "Introducing require-by-string", RFC amendments May 2025; `@game` alias added Jan 2026).
- **Caveat to encode in the client bootstrap:** string requires do NOT wait for ModuleScript replication; gate on `game.Loaded:Wait()` before requiring the ReplicatedStorage mount from a client entry point.
- `@self`/`./` semantics confirmed per RFC = exactly the vendor transform mapping (leaf `./`=siblings; init.luau `@self/`=own children, `./`=siblings of the directory-module). Sources: rfcs.luau.org (abstract-module-paths-and-init-dot-luau, new-require-by-string-semantics), devforum 3405078.

## Input Action System — Client Beta, publishable; test path needs empirical proof

- InputContext: `Enabled`/`Priority`/`Sink` only; enable via property, not parenting. Sink documented in terms of "bound KeyCodes" — sinking of UIButton/Scriptable bindings is NOT documented.
- InputAction: types Bool, Direction1D, Direction2D, **Direction3D**, ViewportPosition; events Pressed/Released (Bool) + StateChanged; `GetState()`/`Fire()` **deprecated** — do not use `InputAction:Fire()`.
- InputBinding: has `UIButton: GuiButton` (touch on-screen binding), `DisplayName`/`DisplayImage`, composite directional keys, thresholds, `Fire(state)`.
- **`InputBinding:Fire()` likely requires `Type = Scriptable`** (community-reported error "InputBinding:Fire() is not enabled" otherwise; devforum 4710232 — NOT in official docs).
- **UNCONFIRMED (load-bearing for design §9.2): whether `Fire()` traverses context priority/sinking like hardware input.** The Studio spike must prove: a higher-priority Sink context blocks a lower-priority scriptable `Fire()`. If it does not, the harness needs a documented fallback (e.g. per-context assertion of enabled/priority state plus action-level traces) — record outcome in the spike ADR.
- `InputAction.PreferredBinding` exists (read-only, semantics undocumented prose-wise).
- IAS status: **Client Beta since 2025-08-20, publishable to live experiences; no GA announcement found.** Coexistence with default control scripts needs `Workspace.PlayerScriptsUseInputActionSystem = Enabled`.
- `UserInputService.PreferredInput`: enum Touch/Gamepad/KeyboardAndMouse; change via `GetPropertyChangedSignal("PreferredInput")`. Still UIS-only: capability flags, on-screen keyboard geometry (`OnScreenKeyboardVisible/Position/Size`), `GetStringForKeyCode`/`GetImageForKeyCode`. GuiService-only: `TopbarInset`, `GetGuiInset()`, `PreferredTransparency`, `ReducedMotionEnabled`, `ViewportDisplaySize`.
