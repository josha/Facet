# First-responder platform research (input for ADR-0014)

Bounded Roblox-platform research: how a Facet surface becomes "first responder" over avatar/gameplay input in a real avatar game, consistent with first-party conventions. Labels: **[VERIFIED]** = stated in official Roblox docs/API; **[INFERRED]** = reasoned from evidence, not stated; **[PROBED]** = from `ui_todo.md` §3 live-Studio truths (not re-verified here).

Produced 2026-07-21 by the fresh-context roblox-platform verifier (xhigh, bounded research run); persisted verbatim by the lead. Director direction that commissioned it: real games set player scripts to the IAS version; never swallow avatar input wholesale — a Facet surface must become first responder via focus awareness (Apple responder-chain analog), consistent with how other Roblox UI handles this; disabling player input is only valid for UI-only places.

## Q1 — The IAS player-script stack, contexts, priorities, sink

- **[VERIFIED]** `InputContext` holds `InputAction`s; `Priority` (int) determines order (higher runs first) and `Sink` (bool), when true, blocks bound actions in *lower-priority* contexts from processing that input. Source: https://create.roblox.com/docs/input/input-action-system and https://robloxapi.github.io/ref/class/InputContext.html
- **[VERIFIED]** The docs' first-party layering pattern is two named contexts: **`PlayContext`** (in-experience character controls) and **`NavContext`** (UI-menu navigation), toggled via each context's `Enabled` — "enable the NavContext when an inventory menu is open… change to the PlayContext when the player closes the menu." Source: input-action-system doc.
- **[VERIFIED]** The doc's only concrete priority number is its recommendation to give a gameplay `PlayContext` **`Priority = 2000` with `Sink`** so it sinks "before the default PlayerScripts contexts process them." This establishes that the default PlayerScripts contexts sit **below 2000**, but their exact priorities are **not published**. Source: input-action-system doc.
- **[VERIFIED]** `InputContext.Priority` default was historically **1000**, changed in engine version 726 (new default not stated in the ref page). Source: https://robloxapi.github.io/ref/class/InputContext.html
- **[INFERRED]** Because the historical default is 1000 and the doc says 2000 sinks the PlayerScripts contexts, the default PlayerScripts (character) contexts most likely live near the 1000 band. The docs do **not** confirm this; there is **no published reserved-range / priority-band table**.
- **[VERIFIED]** Roblox staff confirm that today the default PlayerScripts sink gamepad **ButtonA (jump)** via the legacy **Classic Action Set (CAS)** before custom `InputAction`s can see it; the stated fix is migrating PlayerScripts to IAS, opted into via `Workspace.PlayerScriptsUseInputActionSystem`. Source: https://devforum.roblox.com/t/inputcontext-inputaction-completely-ignore-jump-inputs-on-gamepad/4666924
- **[PROBED]** `Workspace.PlayerScriptsUseInputActionSystem` (the earlier session's note recorded it under StarterPlayer — corrected to Workspace per the official Workspace class reference; platform verifier P2, 2026-07-21) is Properties-panel-only — not script- or rojo-reflectable — so a game cannot toggle it at runtime; Facet must *detect* the mode, not set it (ui_todo §3).

## Q2 — Gamepad UI engagement conventions

- **[VERIFIED]** `GuiService.SelectedObject` is the GuiObject focused by the gamepad navigator; the engine picks the selectable/visible/on-screen object with the smallest `SelectionOrder`; it resets to `nil` if the object goes off-screen; changes fire `SelectionGained`/`SelectionLost`. Source: https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiService.yaml
- **[VERIFIED]** `GuiService.GuiNavigationEnabled` toggles default controller GUI navigation. `AutoSelectGuiEnabled`: the gamepad **Select** button (or backslash) auto-focuses a GUI; disable it and navigation only starts when you set `SelectedObject` manually. Source: GuiService.yaml.
- **[VERIFIED]** `GuiService:Select(parent)` focuses the smallest-`SelectionOrder` descendant; `AddSelectionParent`/`RemoveSelectionGroup` constrain gamepad navigation to a modal subtree ("useful for modal menus"). Source: GuiService.yaml.
- **[VERIFIED]** `GuiService.CoreGuiNavigationEnabled` controls whether CoreGui can be navigated by gamepad. **[PROBED]** it re-enables itself if scripted off (CoreScripts fight back) — cannot be durably suppressed.
- **[INFERRED]** IAS (`InputContext`/`InputAction`) and `GuiService` gamepad selection are **parallel systems**: no doc links them. `GuiService` drives UI focus + `Activated` on the selected object; IAS drives named gameplay actions and their sinking. Claiming gamepad UI focus (set `SelectedObject` / `Select` a modal group) does **not** by itself stop the character from jumping — suppressing jump still requires an input-layer sink (IAS `Sink` or CAS). This is the crux: focus and input-suppression are two separate mechanisms a game must coordinate manually. The docs describe no unified "responder chain."

## Q3 — Touch

- **[VERIFIED]** `UserInputService.ModalEnabled` hides the mobile controls (thumbstick joystick + jump button) on `TouchEnabled` devices; only affects touch (not gamepad/keyboard); `InputBegan`/`TouchSwipe` still fire. It is **deprecated in favor of `GuiService.TouchControlsEnabled`**. Sources: https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UserInputService.yaml and https://devforum.roblox.com/t/replacement-for-modalenabled/2575889
- **[INFERRED]** The sanctioned first-party touch move when a full-screen surface opens is to set `GuiService.TouchControlsEnabled = false` (hides thumbstick + jump), restoring it on close. The doc confirms the *effect*; it does not literally prescribe it as the modal recipe. **[PROBED-adjacent]** Historically `ModalEnabled` has had reliability complaints (some reports it "only hides"); `TouchControlsEnabled` is the current property.

## Q4 — Keyboard / mouse

- **[VERIFIED]** There is no first-party "responder chain" for keyboard/mouse. A panel prevents WASD/Space reaching the character by one of: (a) IAS `Sink` at higher priority than the character context; (b) `ContextActionService:BindAction(..., true, ...)` / `BindActionAtPriority` sinking the key; or (c) `PlayerModule:GetControls():Disable()`. Source: input-action-system doc; https://devforum.roblox.com/t/disable-player-control-without-disabling-mobile-buttons/249206
- **[VERIFIED]** `Controls:Disable()` stops movement wholesale; **[VERIFIED-caveat]** on mobile it also hides the touch GUI (the known cross-platform trap). It is the "UI-only place" hammer — **not** focus-aware / per-action. Source: devforum controls threads.
- **[VERIFIED]** `ContextActionPriority` enum: **Low = 1000, Medium/Default = 2000, High = 3000**. The legacy character jump binds at CAS **2000** (Medium/Default). Source: https://robloxapi.github.io/ref/enum/ContextActionPriority.html; matches ui_todo §3's "CAS prio 2000".
- **[VERIFIED]** `MouseIconEnabled` toggles cursor visibility; `MouseBehavior` ∈ {Default, LockCenter, LockCurrentPosition}. A panel typically wants `MouseBehavior = Default` + `MouseIconEnabled = true` so the pointer is free. Source: UserInputService.yaml.
- **[INFERRED]** Popular frameworks split the same way: full-screen/UI-only → `Controls:Disable()`; in-world panels that must coexist with the avatar → sink specific keys at high CAS/IAS priority while open. No single documented idiom is mandated.

## Q5 — Synthesis for the Facet presenter (input to ADR-0014, not the ADR)

Facet presenter today: base screens = IAS context **priority 1500, non-sinking**; modals = **2000+, sinking**; `opts.sinkNavigation` opt-in.

**Priority band placement.** The docs put a *gameplay* sink at 2000. A Facet modal that also sinks at **2000 ties the game's own `PlayContext`** — tie-break order between two 2000/Sink contexts is **undocumented**. Recommendation for ADR-0014: Facet's engaged-modal band should sit **strictly above the gameplay sink band** (mirror CAS High = 3000), and base non-sinking screens can stay at 1500 (above the ~1000 character default, below gameplay 2000) so they never suppress movement. Treat the exact character-context priority as unknown; rely only on the doc-guaranteed "2000 sinks the defaults," and beat it.

**Engagement / resign transitions per input class (the responder-chain analogue):**
- **Pointer (mouse/touch tap-in):** engage on pointer-down inside the surface → the surface becomes first responder for that gesture. Mouse clicks already route to GUI `Activated` regardless; movement keys are unaffected unless separately sunk. Resign when the surface closes or focus leaves.
- **Gamepad:** engage when `GuiService.SelectedObject` lands inside the surface — set it explicitly on modal open (or via `GuiService:Select`/`AddSelectionParent` to constrain nav to the modal subtree), or let `AutoSelectGuiEnabled` let the user press **Select**. While engaged, **sink ButtonA** in the modal context so it `Activates` the focused control instead of jumping. Resign (clear `SelectedObject` / remove the selection group / disable the modal context) on close.
- **Keyboard activation:** engage on `TextBox` focus (already handled per ui_todo §1's text-entry handshake) or on explicit focus/pointer; sink WASD/Space in the modal context only while a modal actually wants them.
- **Resign (all classes):** disable the Facet modal context, restore `GuiService.SelectedObject`, re-show touch controls (`TouchControlsEnabled = true`), and never leave movement disabled.

**Jump / ButtonA specifically:**
- **IAS mode (flag on):** jump is an `InputAction` in a PlayerScripts context *below* the modal. A modal at a higher priority with `Sink` covering the jump binding's inputs (**ButtonA + Space + the touch jump**) will suppress jump *only while engaged* — this exactly satisfies the director's "focus-aware, never wholesale" requirement. Facet must sink the *same* inputs the character context binds, and only in the modal (never in base 1500 screens).
- **Legacy mode (flag off):** **[PROBED/INFERRED]** jump is bound via legacy CAS at 2000 and consumes ButtonA before IAS fires — a Facet IAS context can **never see or sink it**. The only levers are CAS-level (`BindAction` sink at priority > 2000) or `Controls:Disable()`, neither of which is per-action focus-granular. **The director's requirement is only achievable when the game runs the IAS player-script stack.** ADR-0014 should make "real games set `PlayerScriptsUseInputActionSystem`" a stated precondition, with a legacy fallback that is explicitly coarser.

## Open risks / needs live probe

Points where the platform gives **no sanctioned mechanism**, or where only a Studio session (character present + `PlayerScriptsUseInputActionSystem` set in Properties) can confirm:
1. **Default PlayerScripts context priorities/names are undocumented.** Only "2000 sinks them" is doc-guaranteed. Live probe: read the created `InputContext` instances under PlayerScripts with the flag on to observe actual priorities/names for movement/jump/camera.
2. **Priority tie behavior** between two 2000/Sink contexts is undocumented — live probe needed if Facet ever shares the gameplay band.
3. **Legacy CAS jump cannot be intercepted at the IAS layer** — impossible without the IAS PlayerScripts stack. Confirm the exact set of inputs the IAS jump `InputAction` binds (ButtonA, Space, touch jump) via probe so the modal sinks the complete set.
4. **`GuiService.SelectedObject` ↔ IAS linkage is undocumented** — treat as parallel; probe whether setting `SelectedObject` alone alters any IAS action arbitration (expected: no).
5. **Escape / Roblox menu (ButtonStart, Esc) and CoreGui nav are reserved** — `CoreGuiNavigationEnabled` re-enables itself; cannot be durably suppressed. No mechanism.
6. **`TouchControlsEnabled = false`** as the modal touch recipe is inferred from the effect; confirm on a physical touch device that thumbstick + jump are both suppressed and cleanly restored.
7. **`PlayerScriptsUseInputActionSystem` is Properties-only** — verify no runtime/rojo path exists in the current engine build; Facet must detect, not set.

## Load-bearing conclusions

1. Roblox exposes **no unified "responder chain."** "First responder" must be assembled from two parallel systems: `GuiService` gamepad **focus** (`SelectedObject` / `Select` / `AddSelectionParent`) and an input-layer **sink** (IAS `Sink` or CAS priority). Facet must coordinate both manually.
2. The doc-sanctioned layering idiom is **`PlayContext` vs `NavContext` toggled by `Enabled`**, with a gameplay sink recommended at **`Priority = 2000`**; default PlayerScripts contexts sit below that (historical default 1000). No reserved-band table is published.
3. To be focus-aware and never swallow jump wholesale, Facet must **sink jump inputs only in the engaged modal context, above the gameplay band** — mirror **CAS High (3000)** rather than tying the game's 2000, since the base screens at 1500 stay non-sinking above the ~1000 character default.
4. **This only works in IAS player-script mode.** In legacy mode the character binds jump via CAS at 2000 and eats ButtonA before IAS — the director's requirement is unattainable there; ADR-0014 should require `PlayerScriptsUseInputActionSystem` (Properties-panel-only, not runtime-settable) and offer only a coarser CAS/`Controls:Disable()` fallback.
5. **Gamepad engagement** = set/constrain `GuiService.SelectedObject` on open (optionally via `AddSelectionParent`), sink **ButtonA** while engaged so it Activates instead of jumps, and clear focus on resign. `AutoSelectGuiEnabled`/**Select** is the user-initiated summon path.
6. **Touch modal** = `GuiService.TouchControlsEnabled = false` (the current, non-deprecated replacement for `UserInputService.ModalEnabled`) to hide thumbstick + jump, restored on close.
7. **`Controls:Disable()` is the UI-only-place hammer, not a focus mechanism** — it stops movement wholesale and hides the mobile GUI; unsuitable for avatar-present surfaces.
8. **Hard limits with no sanctioned mechanism:** Escape/Roblox menu and CoreGui gamepad nav are reserved (`CoreGuiNavigationEnabled` re-enables itself); default PlayerScripts priorities/names and any `SelectedObject`↔IAS linkage are undocumented — all require a live Studio probe with a character and the flag set.

## Sources

- https://create.roblox.com/docs/input/input-action-system
- https://github.com/Roblox/creator-docs/blob/main/content/en-us/input/input-action-system.md
- https://robloxapi.github.io/ref/class/InputContext.html
- https://robloxapi.github.io/ref/enum/ContextActionPriority.html
- https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiService.yaml
- https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UserInputService.yaml
- https://devforum.roblox.com/t/inputcontext-inputaction-completely-ignore-jump-inputs-on-gamepad/4666924
- https://devforum.roblox.com/t/studio-beta-new-input-action-system/3656214
- https://devforum.roblox.com/t/replacement-for-modalenabled/2575889
- https://devforum.roblox.com/t/disable-player-control-without-disabling-mobile-buttons/249206
