# Input-architecture inventory — Facet release-candidate review

**Scope** — every direct use of `ContextActionService`, `UserInputService` (all members),
raw `KeyCode`/button event wiring, `GuiObject` `Input*`/`Touch*`/`Activated` events used for
semantic actions, and any parallel action-routing layer, across:

| Tree | Commit / path |
|---|---|
| Facet `src/`, `examples/`, `tools/`, `tests/lib` | `GameStudio/ui/Facet` @ `b230b87` |
| Consumer | `games/RascalRally/code` (`src/`, project files) |

**Platform authority** — `scratchpad/platform-research.md` (fetched live 2026-08-17). Every
"can IAS express it today" answer below cites that document by section. The load-bearing
facts used throughout:

- **§A.2 `InputBinding`** — the complete binding surface is `KeyCode` (`Enum.KeyCode`),
  `UIButton`/`UIModifier` (`GuiButton`), `Up`/`Down`/`Left`/`Right`/`Forward`/`Backward`
  composites, `Scale`/`Vector2Scale`/`Vector3Scale`, `PrimaryModifier`/`SecondaryModifier`,
  `PressedThreshold`/`ReleasedThreshold`, `ResponseCurve`, `PointerIndex`,
  `DisplayImage`/`DisplayName`, `Type` (`Automatic` | `Scriptable`).
- **§A.2 `InputAction`** — `Type` ∈ {Bool, Direction1D, Direction2D, Direction3D,
  ViewportPosition}; events `Pressed`/`Released`/`StateChanged`; `GetState()`;
  **`InputAction:Fire()` is tagged Deprecated**.
- **§A.2 `InputBinding:Fire(state)`** — the live scripted-firing surface; **"can only be
  called on bindings with Type set to Scriptable. Calling it on an Automatic binding will
  throw an error."**
- **§A.4 — what IAS does NOT provide**: pointer position/geometry beyond the raw
  `ViewportPosition` value ("no mention of hit-testing, screen-to-world conversion, or
  geometry helpers"); **text entry — "Not mentioned anywhere"**; **touch gesture
  recognition (swipe/pinch/etc.) — "Not mentioned"**; no device-change event.
- **§A.2 `InputContext.Sink`** — sinks **by key**: "if multiple contexts contain an
  InputAction with a binding to `Enum.KeyCode.E` and a higher priority context has Sink set
  to true, the lower priority contexts will not receive the input signal for
  `Enum.KeyCode.E`". **"Contexts with the same priority will receive the input."**
- **§A.3 rollout** — `Workspace.PlayerScriptsUseInputActionSystem`: Phase 1 (now) opt-in;
  Phase 2 (early 2027) default-on; Phase 3 (mid 2027) property removed.

**Classes** — (1) semantic action routing · (2) environment/capability observation ·
(3) raw pointer/keyboard geometry · (4) engine interoperability/diagnosis ·
(5) test-only injection.

Within class 1, `IAS ✓` marks a use that is *already* on `InputContext`/`InputAction`/
`InputBinding` (compliant, no migration owed); `LEGACY` marks a semantic verb still routed
through a non-IAS engine surface (migration candidate — see the per-item notes).

---

## 1. Classified table

### 1a. Facet `src/client/roblox_input.luau` — the IAS adapter (the one allowlisted action seam)

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-1 | `src/client/roblox_input.luau:54-59` | `createContext` → `Instance.new("InputContext")`, sets `Name`/`Priority`/`Sink`, parents to `PlayerScripts` | 1 · IAS ✓ |
| INPUT-2 | `:71-75` | `createAction` → `Instance.new("InputAction")`, `Type` from `Enum.InputActionType[actionType]` | 1 · IAS ✓ |
| INPUT-3 | `:88-109` | binds `StateChanged` / `Pressed` / `Released` to the framework's handler lists | 1 · IAS ✓ |
| INPUT-4 | `:158-212` | modifier-gated bind: **two** `InputBinding`s with `PrimaryModifier` = Left/RightShift (no combined Shift enum) | 1 · IAS ✓ |
| INPUT-5 | `:214-241` | plain bind → `InputBinding`: `Type = Scriptable`, or `KeyCode`, or `Up`/`Down` composite slots for `Direction1D`, plus `UIButton` and `DisplayName` | 1 · IAS ✓ |
| INPUT-6 | `:185-200`, `:252-260` | `binding.fire()` → `InputBinding:Fire(value)`, `pcall`-wrapped | 1 · IAS ✓ (defect note ①) |
| INPUT-7 | `:288-366` | `bindAxis`: companion `Direction2D` `InputAction` + `Thumbstick1` `InputBinding`, then a **Luau-side deadzone/re-center latch** converting the analog stream to discrete presses | 1 · IAS ✓ + 3 |
| INPUT-8 | `:368-387` | `action.preferredBinding` reads `InputAction.PreferredBinding`, falls back to a `preferredInput`-keyed scan | 2 |
| INPUT-9 | `:393-405` | `setEnabled`/`setSink` → `InputContext.Enabled` / `.Sink` (the ADR-0014 responder writes) | 1 · IAS ✓ |
| INPUT-10 | `:407-425` | `destroy` — disconnect, dispose signals, `contextInstance:Destroy()` | 1 · IAS ✓ |
| INPUT-11 | `:13`, `:23-34` | `UserInputService:IsKeyDown` ×6 (Left/RightShift, Left/RightControl, Left/RightMeta) → `system.modifiers()` | **3** |

**Defect note ①** — `binding.fire` calls `InputBinding:Fire()` on bindings that are
`Automatic` (the modifier path at `:185-200` explicitly documents this, and the ordinary
path at `:252-260` fires whatever the binding is). Per §A.2 that **throws**; the `pcall`
swallows it, so the call is a silent no-op rather than an error. Interface-shape parity is
the stated reason. Not a correctness bug today (nothing calls it on an Automatic binding in
production) but it means a caller cannot distinguish "fired" from "silently refused".

### 1b. Facet `src/client/roblox_env.luau` — the one allowlisted environment reader

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-12 | `src/client/roblox_env.luau:7`, `:102-113` | `UserInputService.PreferredInput` + `KeyboardEnabled` / `MouseEnabled` / `TouchEnabled` / `GamepadEnabled` → `env.preferredInput` + `env.capabilities` | 2 |
| INPUT-13 | `:191` | `UserInputService:GetPropertyChangedSignal("PreferredInput")` | 2 |
| INPUT-14 | `:198-199` | `UserInputService.GamepadConnected` / `.GamepadDisconnected` | 2 |
| INPUT-15 | `:200-202` | `GetPropertyChangedSignal` on each of the four `*Enabled` capability properties | 2 |
| INPUT-16 | `:203-211` | `UserInputService.LastInputTypeChanged` → sticky `sawGamepadInput` (ADR-0015: `GamepadEnabled=false` with a working pad is a documented engine failure class) | 2 |
| INPUT-17 | `:226-239` | `OnScreenKeyboardVisible` / `…Position` / `…Size` → `env.keyboardOcclusionRect` | 2 |
| INPUT-18 | `:8`, `:22-76`, `:180-190` | `GuiService:GetGuiInset` / `GetInsetArea` / `TopbarInset` / `ViewportDisplaySize` (+ change signals) | 2 |
| INPUT-19 | `:163-174`, `:212-225` | `GuiService.ReducedMotionEnabled` / `.PreferredTransparency` / `.PreferredTextSize` (+ change signals) | 2 |

### 1c. Facet `src/client/gamepad_contention.luau` — the CAS diagnosis/repair module

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-20 | `src/client/gamepad_contention.luau:158-165` | `legacyStackActive()` → `ContextActionService:GetAllBoundActionInfo()`, looks for `jumpAction` | 4 |
| INPUT-21 | `:203-222` | `cameraKeysContended(boundActionInfo?)` → same CAS read, scans `info.inputTypes` for the four arrow `KeyCode`s (string-compared so it runs headless) | 4 (+5: injectable seam) |
| INPUT-22 | `:245-251` | `traversalKeyContended()` → `StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)` — the documented Tab-reservation condition | 4 |
| INPUT-23 | `:271-297` | `disableLegacyControls(parent?)` → `PlayerModule:GetControls():Disable()`, **fallback `ContextActionService:UnbindAction("jumpAction")`** — the only *mutating* legacy call in `src/` | 4 (+5: injectable seam) |
| INPUT-24 | `:89-146` | `describeContention()` — the five engine truths as a diagnostic string | 4 |

### 1d. Facet `src/client/screen_pointer.luau` — the pointer seam

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-25 | `src/client/screen_pointer.luau:56-59` | writes `UserInputService.MouseIcon` from the semantic cursor hint | 3 |
| INPUT-26 | `:85-122` | `pointerActivateMeta` — reads `InputObject.UserInputType`/`.Position`, `IsKeyDown` ×6, `GuiService:GetGuiInset()`; produces `{ pointer, x, y, shift, toggle }` | 3 |
| INPUT-27 | `:124-134` | `setActivateHandler` → **`GuiButton.Activated`** drives the control's activate verb | **1 · LEGACY** |
| INPUT-28 | `:166-168` | `GuiService.MenuOpened` → aborts any live pointer capture (Escape is core-reserved) | 4 |
| INPUT-29 | `:294-382` | `beginPointerCapture` — global `UserInputService.InputChanged` + `.InputEnded` for the life of a drag, filtered to `MouseButton1`/`Touch`/`MouseMovement` | 3 |
| INPUT-30 | `:385-389` | `connectPointerBegan` → `GuiObject.InputBegan` opens the capture | 3 |
| INPUT-31 | `:405-414` | `MouseEnter`/`MouseLeave` on a `Grip` → hover cursor hint | 3 |
| INPUT-32 | `:419-429` | `setScrollHandler` → `InputChanged` filtered to `MouseWheel`, delivers `Position.Z` | **1 · LEGACY** |

### 1e. Facet `src/client/screen_target.luau` — the render adapter

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-33 | `src/client/screen_target.luau:2231-2240` | hit-expander `TextButton.Activated` → the host control's activate, with the *same* `pointerActivateMeta` | **1 · LEGACY** |
| INPUT-34 | `:2317-2377` | `UIDragDetector` (`CustomOffset`) `DragStart`/`DragContinue`/`DragEnd` | 3 |
| INPUT-35 | `:2402-2415` | `setSecondaryActivate` → `GuiObject.InputBegan` filtered to `Enum.UserInputType.MouseButton2` → the `.contextMenu` verb | **1 · LEGACY** |
| INPUT-36 | `:2433-2462` | `setTouchGestureHandlers` → `TouchTap`, `TouchLongPress`, `TouchPan`, `TouchPinch`, `TouchRotate`, `TouchSwipe` normalized by `src/input/touch_gestures` | **1 · LEGACY** |
| INPUT-37 | `:2518-2576` | `setTextInputHandlers` → `TextBox` `GetPropertyChangedSignal("Text")`, `.Focused`, `.FocusLost(enterPressed, input)` (reads `input.KeyCode == ButtonB/Escape` to classify cancel), `.ReturnPressedFromOnScreenKeyboard` | **1 · LEGACY** |
| INPUT-38 | `:2604-2607` | `enableHover` → `MouseEnter` (hover fill; only wired when the pointer class is live) | 3 |
| INPUT-39 | `:2624-2707` | `enableDisclosure` → `MouseEnter`/`MouseLeave` + `InputBegan` filtered to Touch, then **global `UserInputService.InputChanged`/`.InputEnded` filtered to that exact `InputObject`** for a 0.4 s / 12 px long-press | **1 · LEGACY** (built on 3) |
| INPUT-40 | `:2467-2510` | mirrors Facet logical focus onto `GuiService.SelectedObject` for opted-in modals only | 4 |
| INPUT-41 | `:3388-3400` | `TextBox:IsFocused()` / `CaptureFocus` / `ReleaseFocus` reconcile | 4 |

### 1f. Facet — remaining `src/client/`

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-42 | `src/client/screen_paint.luau:473-483` | icon-button press dip: `MouseButton1Down` / `MouseButton1Up` / `MouseLeave` (**visual state only**) | 3 |
| INPUT-43 | `src/client/screen_paint.luau:877-905` | interactive-state fill + press dip: `MouseLeave` / `MouseButton1Down` / `MouseButton1Up` (**visual state only**) | 3 |
| INPUT-44 | `src/client/responder_effects.luau:32-48` | reads/writes `GuiService.TouchControlsEnabled` while an exclusive Facet surface is up (the non-deprecated replacement for `UserInputService.ModalEnabled`) | 4 |
| INPUT-45 | `src/client/haptics.luau:445-489` | device probe: `UserInputService:GetConnectedGamepads()` + `HapticService:IsVibrationSupported(pad)`; service handle is injectable (`options.inputService`) | 2 (+5) |
| INPUT-46 | `src/client/haptics.luau:504-520` | re-probes on `GamepadConnected` / `GamepadDisconnected` / `LastInputTypeChanged` | 2 |

### 1g. Facet — the parallel action-routing layer and the pure input model

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-47 | `src/input/actions.luau` (whole, 451 lines) | **engine-free reimplementation of IAS semantics** — contexts, typed actions, bindings, priority/Sink arbitration (`deviceKey`, `:356-414`), scriptable-bypass, modifier matching (`modifierMatch`, `:341-352`) | **5** (parallel routing layer) |
| INPUT-48 | `src/init.luau:157` | `Facet.newActionSystem = actionsLib.newSystem` — the headless model is a **public export** | 5 (public escape hatch — see risk DF-11) |
| INPUT-49 | `src/input/touch_gestures.luau:1-279` | normalizes the six engine gesture callbacks into value objects; **positional** arg reading (`:129+`); no engine call | 3 (pure) |
| INPUT-50 | `src/input/drag_registry.luau:838-880`, `src/input/spatial.luau`, `src/input/autoscroll.luau` | pure promotion/threshold/velocity math; document the `UIDragDetector` path but never touch the engine | 3 (pure) |
| INPUT-51 | `src/controls/text_input.luau:270-289` | text-entry context: priority `10000`, `sink = true`; `Swallow` (`Direction1D`) bound to Up/Down/Left/Right + the four DPads, `Cancel` bound to `ButtonB` | 1 · IAS ✓ |
| INPUT-52 | `src/controls/row_actions.luau:211-213` (`ROW_KEYS`), `:2225-2228` | row-actions context: priority `10000`, `sink = true`; `RowActionsDelete` ← Delete/Backspace, `RowActionsMenu` ← ButtonX and **Return + `modifiers.shift`** | 1 · IAS ✓ (see risk DF-6) |

### 1h. Facet `src/present/presenter.luau` — the semantic verb layer

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-53 | `src/present/presenter.luau:2184-2196` | nav `createContext` with the priority band (base `1500`, engaged `3000`, modal `+500`/depth) and the sink rule (`modal or (not passive and (sinkNavigation or keyboardNavigation))`) | 1 · IAS ✓ |
| INPUT-54 | `:2197-2249` | `Navigate` / `Activate` / `Cancel` / `Adjust` / `AdjustAxis` / `Traverse` / `NavigateH` actions; Up/Down + DPadUp/DPadDown + `bindAxis Thumbstick1.y`; Left/Right + DPadLeft/Right + `Thumbstick1.x` | 1 · IAS ✓ |
| INPUT-55 | `:2251-2267` | `Activate` ← `Return`, `ButtonA`; `Adjust` ← Left/Right, Comma/Period, DPadLeft/Right, ButtonL1/R1 (only when `opts.onAdjust`) | 1 · IAS ✓ |
| INPUT-56 | `:2330-2383` | dynamic `Adjust`/`AdjustAxis` rebinding (yield-and-reclaim of directional keys) | 1 · IAS ✓ |
| INPUT-57 | `:2417` | `Cancel` ← `ButtonB` (Escape is core-reserved, D1) | 1 · IAS ✓ |
| INPUT-58 | `:2440-2492` | `GameplayGuard` ← `Space` (no-op sink) *xor* `Activate` ← `Space` + `Traverse` ← `Tab`, swapped reactively by `setKeyboardBound` on keyboard capability × engaged responder | 1 · IAS ✓ |
| INPUT-59 | `:3074`, `:3178`, `:3204-3205` | `actionSystem.modifiers()` reads — Shift for reorder-nav, Shift for `Traverse` direction, shift/toggle for list selection | 3 (via INPUT-11) |
| INPUT-60 | `:330-400` | `dispatchActivate` — the **double-fire mitigation**: cross-source `{IAS Activate, non-pointer native Activated}` pairs inside `ACTIVATE_ECHO_WINDOW = 0.05 s` collapse to one activation, identified by input *class* (`meta.pointer == "keyboard"/"gamepad"`), never by time alone | 4 |

### 1i. Facet `examples/`

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-61 | `examples/gallery/client/init.client.luau:154-157` | `gamepad_contention.disableLegacyControls()` at boot (UI-only place) | 4 |
| INPUT-62 | `examples/gallery/client/init.client.luau:174-179` | `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)` to free `Tab` | 4 |
| INPUT-63 | `examples/performance/client/init.client.luau:31`, `:157` | `UserInputService.TouchEnabled` in the capture's `deviceLabel` string | 2 |
| INPUT-64 | `examples/performance/client/init.client.luau:66-72` | same `disableLegacyControls()` + `SetCoreGuiEnabled(PlayerList, false)` pair | 4 |
| INPUT-65 | `examples/gallery/scenarios/runner.luau:821-869` | `rawInput` probe: `UserInputService.InputBegan` / `.InputEnded`, records `UserInputType`, `KeyCode`, `Position`, `gameProcessed`, `os.clock()` | 5 |
| INPUT-66 | `examples/gallery/scenarios/runner.luau:882-926` | `keyLog` probe: same two events, Keyboard-filtered, appended as an ordered sequence with `gameProcessed` | 5 |
| INPUT-67 | `examples/gallery/scenarios/runner.luau:1184-1188` | `ContextActionService:UnbindAction("RbxCameraKeypress")` for `keyboardFirst` scenarios | 4 |
| INPUT-68 | `examples/gallery/scenarios/keyboard_navigation.luau:324-350` | reads `StarterPlayer.PlayerModule.InputContexts.CharacterContext` `JumpAction`/`MoveAction` and counts their `Pressed`/`StateChanged` — the arbitration counter-witness | 5 |
| INPUT-69 | `examples/gallery/scenarios/keyboard_navigation.luau:154-170`, `:313-318` | reads the surface's own actions (`handle.actions.*`) and drives `handle.context.setSink()` | 5 |

### 1j. Facet `tools/`

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-70 | `tools/studio/device_matrix.luau:117-131` | one cached `UserInputService:CreateVirtualInput()` for the driver's lifetime | 5 |
| INPUT-71 | `tools/studio/device_matrix.luau:850-880` | VirtualInput pointer drive (aim from the mounted control's live rect) | 5 |
| INPUT-72 | `tools/studio/device_matrix.luau:930-975` | `VirtualInput:SendKey` sequences, holding `LeftShift` across a press so `IsKeyDown` sees it | 5 |
| INPUT-73 | `tools/check_no_screen_key_bindings.py` (whole) | **DK-16 drift check**: no module under `src/controls/` may name `KeyCode` / `UserInputService` / `ContextActionService` in code; `keyCode =` sites pinned to exactly `row_actions.luau` (4) and `text_input.luau` (2); fixture must wire nothing | 4 |
| INPUT-74 | `tools/lune/check_example_drift.luau:150` | `{ pattern = "UserInputService", what = "direct input routing" }` — forbidden in the reference proofs | 4 |
| INPUT-75 | `tools/lune/gate_manifest.luau:118` | reference-proof grep: no `Instance.new` / `GetService(` / `UserInputService` / wall-clock / random under `examples/reference/` | 4 |
| INPUT-76 | `tools/lune/gate_manifest.luau:853`, `:1291`, `:1297`, `:1303`, `:3970` | gate rows that pin the DK-16 check, the contention module, the responder `setSink`, the input guide, and the release-candidate IAS row | 4 |

### 1k. Facet `tests/lib`

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-77 | `tests/lib/fake_target.luau:1114`, `:1631-1645`, `:1831` | models the engine's `InputBegan` → `InputEnded` → `Activated` ordering (and the "whichever side of `InputEnded`" truth) in the headless fake. **No `GetService` anywhere in `tests/lib` — verified.** | 5 |
| INPUT-78 | `tests/lib/gui_value_shim.luau` | installs `UDim2.fromOffset` / `Path2DControlPoint` so `applyRect` runs headless; no input surface | 5 |

### 1l. `Workspace.PlayerScriptsUseInputActionSystem` declarations

| # | project file | declared? |
|---|---|---|
| INPUT-79 | `examples/gallery.project.json:11` | **✅ `"Enabled"`** |
| INPUT-80 | `examples/performance.project.json:15` | **✅ `"Enabled"`** |
| INPUT-81 | `examples/showcase.project.json:15` | **✅ `"Enabled"`** |
| INPUT-82 | `tools/build_places.sh:71` — the generated project for the **8 tutorial example places** | **❌ MISSING** (only `FilteringEnabled`) |
| INPUT-83 | `tools/build_places.sh:143` — the generated project for **`examples/places/Facet-Showcase.rbxl`** | **❌ MISSING** — and this is the file device passes actually open, while the *tracked* `examples/showcase.project.json` (used only by `rojo serve`) does declare it. The served place and the built place therefore differ in input topology. |
| INPUT-84 | `tools/build_reference_places.sh:45` — the generated project for the reference-proof places | **❌ MISSING** |
| INPUT-85 | `games/RascalRally/code/default.project.json:49-59` | **❌ MISSING** — Workspace declares `AuthorityMode`, `SignalBehavior`, `FilteringEnabled`, streaming, gravity, `PhysicsSteppingMethod`, but not this. The live place *has* it ticked (proved by `docs/DECISIONS.md:612`, which describes `Player.InputContexts.CharacterContext` existing — those contexts only exist under the flag), so the production input topology is an **unversioned, hand-set Studio property**. |
| INPUT-86 | `games/RascalRally/code/places/debug.project.json` | **❌ MISSING** — same, for the debug place (`docs/DEBUG_PLACE.md:46` tells a human to tick it by hand). |

**The "not rojo-reflectable" claim is now half-obsolete.**
`src/client/gamepad_contention.luau:26-29` states the property "is NOT script- or
rojo-reflectable; code can neither read nor set it." The **rojo half is false** as of the
pinned toolchain: `tools/build_places.sh:12-16` records the 2026-08-15 measurement that a
stale `/usr/local/bin/rojo` failed on the property while the rokit-pinned 7.7.0 builds it
fine, and three checked-in project files set it. The **script-read half stands** (re-probed
`0.734.0.7340915`). The module comment should be corrected — it is currently the reason
INPUT-82/83/84/85/86 were never fixed.

### 1m. RascalRally — IAS-native core

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-87 | `src/shared/InputActions.luau:24-95` | the device-agnostic action schema (`steer`, `steerTouch`, `steerAssist`, `brakeStick`, `throttle`, `throttleStick`, `brake`, `drift`, `item`, `cameraToggle`, `debugReset`) with `type` / `keyboard` / `gamepad` / `touch` / `fired` / `clientOnly` / `edge` | 1 · IAS ✓ |
| INPUT-88 | `src/server/InputRig.luau:56-93` | **server-created** `DriveInputs` `InputContext` under each `Player`; `newAction` / `bindKey` / `bindComposite` build every hardware binding; `fired` actions get none | 1 · IAS ✓ · **no `Priority`, no `Sink`** |
| INPUT-89 | `src/client/InputBridge.luau:266-296` | client-local `ClientInputs` `InputContext` under the touch GUI: `cameraToggle` (Bool) ← `C`, `V`, `ButtonY` **and `UIButton = buttons.cameraToggle`** | 1 · IAS ✓ · **no `Priority`, no `Sink`** |
| INPUT-90 | `src/client/InputBridge.luau:330-336` | `for action, v in pending do action:Fire(v) end` — **`InputAction:Fire()`, DEPRECATED (§A.2)** | **1 · must migrate** |
| INPUT-91 | `src/client/InputBridge.luau:337-343` | `steerTouch:Fire(touchSteer)` on change — deprecated | **1 · must migrate** |
| INPUT-92 | `src/client/InputBridge.luau:394-403` | `brakeStick:Fire()` / `throttleStick:Fire()` on wedge-latch edges — deprecated | **1 · must migrate** |
| INPUT-93 | `src/client/AssistPilot.luau:84`, `:177`, `:219` | `steerAssist:Fire(...)` from `RenderStepped` — deprecated | **1 · must migrate** |
| INPUT-94 | `src/server/FTUESession.luau:112-120` | server-side `InputAction:GetState()` read of the player's merged steer | 1 · IAS ✓ |
| INPUT-95 | `src/client/SponsorGesture.luau:330-392` | `SponsorInputs` `InputContext` under the sponsor GUI: `sponsorCancel` ← `Escape`+`ButtonB`; `sponsorMapToggle` ← `ButtonY`; `sponsorWatchPrev/Next` ← `ButtonL1`/`ButtonR1`; `Enabled` derived from the current view | 1 · IAS ✓ · **no `Priority`, no `Sink`** |
| INPUT-96 | `src/client/SponsorResults.luau:2607-2630` | `ResultsSkipInputs` `InputContext`: `resultsSkip` ← `Space` + `ButtonX`; `Enabled` derived by `_setSkipEnabled` | 1 · IAS ✓ · **no `Priority`, no `Sink`** |
| INPUT-97 | `src/client/init.client.luau:263-310` | holds `Player.InputContexts.CharacterContext` / `CameraContext` / `VehicleContext` `Enabled = false`, re-asserted via `GetPropertyChangedSignal("Enabled")` + `ChildAdded` + `CharacterAdded` | 4 |
| INPUT-98 | `src/client/MinClient.luau:105-130` | the same silencing, for the minimal client harness | 4 |

### 1n. RascalRally — legacy `UserInputService` / `GuiObject` surfaces

| # | file:line | what it does | class |
|---|---|---|---|
| INPUT-99 | `src/client/InputIdentity.luau:25`, `:36-39` | boot capability read: `TouchEnabled`, `GamepadEnabled` | 2 |
| INPUT-100 | `src/client/InputIdentity.luau:63-76` | `UserInputService.InputBegan` → deliberate-act identity classifier (touch/keyboard/mouse/gamepad-button) | 2 |
| INPUT-101 | `src/client/InputIdentity.luau:78-85` | `UserInputService.InputChanged` → gamepad identity only past a `0.25` thumbstick deadzone (drift never claims identity) | 2 |
| INPUT-102 | `src/client/InputBridge.luau:111-127` | `UserInputService.TouchStarted` → drag-anywhere steer grab, gated on `gameProcessed` + `sponsoringNow` + `modalNow` | 3 |
| INPUT-103 | `src/client/InputBridge.luau:129-138` | `UserInputService.TouchMoved` → steer / drag-up values | 3 |
| INPUT-104 | `src/client/InputBridge.luau:140-146` | `UserInputService.TouchEnded` → release | 3 |
| INPUT-105 | `src/client/InputBridge.luau:302-323` | `stageButton`: on-screen `GuiButton.InputBegan` (Touch/MouseButton1) stages `true`, global `UserInputService.InputEnded` (identity-matched to the press object) stages `false`, flushed as `drift`/`item` `Fire()`s | **1 · LEGACY** |
| INPUT-106 | `src/client/SponsorGesture.luau:55`, `:431-440` | `UserInputService.TouchMoved` / `.TouchEnded` → card drag | 3 |
| INPUT-107 | `src/client/SponsorGesture.luau:443-469` | `UserInputService.InputChanged` (MouseMovement) / `.InputEnded` (MouseButton1) → mouse drag + press-candidate promotion | 3 |
| INPUT-108 | `src/client/SponsorGesture.luau:519-550`, `:596-615` | `InputObject.Changed` on the *pressed object itself* → identity-proof touch move/release (a UIS-identity match had missed on mobile and latched `_dragActive`) | 3 |
| INPUT-109 | `src/client/SponsorGesture.luau:398-420`, `:1425-1440`, `:1853` | `GuiService:GetPropertyChangedSignal("SelectedObject")` + reads/writes of `GuiService.SelectedObject` (ghost-follows-focus; driving view forces it `nil`) | 4 |
| INPUT-110 | `src/client/SponsorResults.luau:35`, `:2570-2578` | `UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonX)` → platform-correct skip glyph | 2 |
| INPUT-111 | `src/client/DriverHints.luau:38`, `:230` | `UserInputService:GetImageForKeyCode(key)` → per-action hint glyphs | 2 |
| INPUT-112 | `src/client/FacetSettingsGui.luau:24`, `:96-102`, `:269` | `UserInputService.GamepadEnabled` gates mirroring Facet focus onto `GuiService.SelectedObject`; cleared on close | 2 + 4 |
| INPUT-113 | `src/client/ItemFx.luau:44` | `local UserInputService = game:GetService("UserInputService")` — **zero uses in the file; dead import** | 4 (dead) |
| INPUT-114 | `src/client/SponsorGui.luau:807-819` | card slot `InputBegan` → `beginPressCandidate` (drag-vs-tap discrimination) | 3 |
| INPUT-115 | `src/client/SponsorFtue.luau:493` | slot `InputBegan` → FTUE step advance | 3 |
| INPUT-116 | `src/client/SponsorGui.luau:613`, `:620`, `:821`, `:909`, `:1003`, `:1626`; `SponsorRacerList.luau:264`, `:265`, `:489`; `SettingsGui.luau:193`, `:251`, `:426`; `SponsorResults.luau:486`, `:489`, `:557`, `:1584`; `DebugHud.luau:123`, `:164`, `:202`, `:239`, `:265`; `FacetSettingsGui.luau:171` | **22 `GuiButton.Activated:Connect` sites** carrying semantic verbs (race/chaos, restore, resize, racer select, settings open/close/choose, skip, next race, dev reset, buzz, vet) | **1 · LEGACY** |

---

## 2. Class counts

| Class | Rows (primary) | Notes |
|---|---:|---|
| **1 — semantic action routing** | **36** | 23 already on IAS (`IAS ✓`) · 9 still routed through a legacy engine surface · 4 on the **deprecated** `InputAction:Fire()` |
| **2 — environment/capability observation** | **18** | |
| **3 — raw pointer/keyboard geometry** | **21** | + 2 secondary (INPUT-7, INPUT-39) |
| **4 — engine interoperability/diagnosis** | **30** | 22 code rows + the 8 project-file rows (INPUT-79…86); includes the 5 drift/gate checks |
| **5 — test-only injection** | **11** | + 3 secondary (INPUT-21, 23, 45); includes the parallel routing layer (INPUT-47/48) |
| **Total rows** | **116** | INPUT-1 … INPUT-116 |

Primary classes partition the 116 rows exactly (36 + 18 + 21 + 30 + 11 = 116). Five rows
carry a second class, noted in their own row and in the "+ secondary" counts above.

**Class-1 breakdown — the 13 rows that are not already compliant:**

| Verdict | Count | Rows |
|---|---:|---|
| **MUST migrate** (IAS expresses it today) | **5** | INPUT-90, 91, 92, 93 (deprecated `InputAction:Fire`) · INPUT-105 (`UIButton` binding) |
| **Cannot migrate** (no IAS surface exists) | **6** | INPUT-32, 35, 36, 37, 39, 116 |
| **Partially expressible — keep** (payload loss) | **2** | INPUT-27, 33 |

---

## 3. Class-1 migration notes — can IAS express it today?

The 11 class-1 rows still on a legacy surface, each against the researched IAS surface.

### 3.1 MUST migrate (IAS expresses it today) — 5 rows, in 2 changes

*(M-3 below is not a class-1 row — it is the project-file prerequisite both migrations and
every arbitration claim rest on, recorded here because it is the same decision.)*

**M-1 · INPUT-90/91/92 (`InputBridge.luau:330-343`, `:394-403`) and INPUT-93
(`AssistPilot.luau:177`, `:219`) — `InputAction:Fire()` is deprecated.**
6 call sites across 2 files. §A.2 tags `InputAction.Fire` **Deprecated** on the live
reference page; the sanctioned replacement is `InputBinding:Fire(state)` on a binding whose
`Type` is `Scriptable` — *"Programmatically updates the parent InputAction to the given
state and fires the appropriate signals… This method respects the same deduplication rules
as hardware input."* The five `fired = true` actions (`steerTouch`, `steerAssist`,
`brakeStick`, `throttleStick`, `debugReset`) already have **no hardware bindings**
(`InputRig.luau:69-70` skips them), so each needs exactly one child `InputBinding` with
`Type = Scriptable`, created beside the action in `InputRig.build`, and the client Fires
*that* instead of the action. Zero behavioural change: the dedup rule is identical and
`InputBinding:Fire` fires the same `Pressed`/`Released`/`StateChanged`. **This is the one
migration with no contract loss and no open question.** Note the two `pending`-flush Fires
(`drift`, `item`) target actions that *do* carry hardware bindings — see M-2, which removes
those Fires entirely rather than converting them.

**M-2 · INPUT-105 (`InputBridge.luau:302-323`) — on-screen touch buttons → `drift`/`item`.**
Expressible today, exactly: §A.2 `InputBinding.UIButton` — *"GuiButton to connect to a
boolean action."* `drift` and `item` are both `Bool` actions that already exist under the
server-created `DriveInputs` context; adding one `InputBinding` per button with
`UIButton = buttons.drift` / `buttons.item` replaces the whole `stageButton` mechanism —
the `InputBegan` listener, the global `UserInputService.InputEnded` identity match, the
`pending` table, the per-frame flush, and the two deprecated `Fire` calls. The
drag-off-then-release bug the comment at `:298-301` exists to work around is **fixed at the
engine level as of 2026-04-07** (§A.6 case 1, staff confirmation: "the `Released` event will
now fire" when the pointer leaves the `UIButton` bounds while pressed) — so the reason the
manual staging existed is gone. The camera-toggle button at `:284-288` already uses
`UIButton`; this is the same pattern, applied consistently. **Prior need is obsolete —
recheck confirmed.**

**M-3 · INPUT-82/83/84/85/86 — `Workspace.PlayerScriptsUseInputActionSystem` in five
project files.** Not a code migration but a class-1 *routing* fact: with the flag off, the
engine's own player scripts stay on `ContextActionService` and (per
`gamepad_contention.luau:50-73`, measured live 2026-08-14) **no `InputContext.Priority`
outranks a sinking CAS `CoreScript` binding at any number**. Every Facet place that ships
without the flag therefore has an input topology no framework arbitration can repair. The
rojo toolchain can set it (see §1l); the property becomes default-on in early 2027 and is
removed mid-2027 (§A.3), so declaring it now is also the forward-compatible state.

### 3.2 CANNOT migrate today — IAS has no surface (6 rows)

| Row | Verb | Missing IAS surface (cited) |
|---|---|---|
| INPUT-32 `screen_pointer:419-429` | mouse-wheel scroll delta | §A.2 — `InputBinding.KeyCode` is `Enum.KeyCode`; the documented action types are Bool / Direction1D / Direction2D / Direction3D / ViewportPosition. **No wheel input source is documented anywhere in IAS**, and `ViewportPosition` delivers a position, not a delta. |
| INPUT-35 `screen_target:2402-2415` | `.contextMenu` (secondary pointer button on *this node*) | §A.2 — the only pointer-ish binding sources are `KeyCode`, `UIButton`, `PointerIndex` (no prose at all on the page). §A.4 — **"Pointer position/geometry: Not addressed as a general capability… no mention of hit-testing"**. Even if a secondary-button source existed, IAS carries no per-node targeting, and this verb is *per node*. |
| INPUT-36 `screen_target:2433-2462` | six touch gestures (tap / longPress / pan / pinch / rotate / swipe) | §A.4 — **"Touch gesture recognition (swipe/pinch/etc.): Not mentioned. Touch is only discussed via `InputBinding.UIButton`… and `PointerIndex`; no gesture-recognition surface… is documented anywhere in IAS."** |
| INPUT-37 `screen_target:2518-2576` | text-entry begin / commit / cancel + OSK return | §A.4 — **"Text entry: Not mentioned anywhere on the overview page or the three class references."** `TextBox.Focused` / `.FocusLost(enterPressed, input)` is the only surface that reports *why* editing ended. (The `ButtonB`/`Escape` cancel classification at `:2559` is a *fallback* for the no-`actionSystem` case; with an action system the control's own `ButtonB` IAS binding ends editing first — `src/controls/text_input.luau:281-284`.) |
| INPUT-39 `screen_target:2624-2707` | full-value disclosure long-press | §A.4 gestures gap, as INPUT-36; and the 12 px slop / one-finger identity match needs `InputObject` identity, which IAS never exposes. |
| INPUT-116 (RascalRally, 22 sites) | menu/HUD button taps | Expressible *in principle* via `UIButton` (§A.2) but each would need its own `InputAction` + `InputContext` placement, and IAS delivers only a boolean — these buttons are one-off, non-contended, pointer-only affordances. **Not required**; converting them would add 22 actions and buy nothing. Recorded as knowingly-kept. |

### 3.3 PARTIALLY expressible — migration would lose contract (2 rows)

**INPUT-27 (`screen_pointer:124-134`) and INPUT-33 (`screen_target:2231-2240`) —
`GuiButton.Activated` → the control's activate verb.**
§A.2 `InputBinding.UIButton` *can* bind a `GuiButton` to a `Bool` action, so the *press
signal* is expressible. What is **not** expressible is the payload: `Activated` hands the
adapter an `InputObject`, and `pointerActivateMeta` (INPUT-26) derives from it
`pointer` ∈ {mouse, touch, gamepad, keyboard}, the window-space tap `x`/`y` (for modal
Zone-A geometry), and the held `shift`/`toggle` modifiers. IAS's `Pressed` signal carries
**no arguments at all** (§A.2: `Pressed(): RBXScriptSignal`), and §A.4 confirms there is no
pointer-geometry surface. Losing that meta is not cosmetic — the repo records it as a HIGH
defect (`screen_pointer:61-84`, the lesson
`docs/lessons/a-synthesized-activate-must-carry-the-pointer-kind.md`): a meta-less activate
made every finger landing in a 44 px hit-expander overhang read as a **mouse click**,
breaking multi-select and handing a phone a double-tap-to-open. It is also what
`dispatchActivate`'s echo collapse (INPUT-60) keys on. **Keep as-is until IAS delivers an
input-object payload on `Pressed`.**

---

## 4. Double-fire risk list

*A path where an IAS action and a legacy listener (or a second IAS context) can both respond
to one physical input.*

### 4.1 OPEN — RascalRally

**DF-1 · gamepad `ButtonB` — `sponsorCancel` and `brake`, same press. CONFIRMED.**
`SponsorGesture.luau:344-346` binds `ButtonB` on `SponsorInputs`;
`InputActions.luau:60-64` gives `brake` gamepad `ButtonB` on the server-created
`DriveInputs`. **Neither context sets `Priority` or `Sink`** (verified: `grep -rn
"\.Priority\s*=\|\.Sink\s*=" src` returns nothing across the whole game). Per §A.2,
*"Contexts with the same priority will receive the input."* One B press therefore both
cancels the aim and brakes. Already logged in `docs/DECISIONS.md:612` as "the sponsor-view
B-cancel-vs-brake tie remains the one logged residual" — this inventory confirms it is
structural, not incidental.

**DF-2 · keyboard `Space` — `resultsSkip` and `drift`, same press.**
`SponsorResults.luau:2620-2622` binds `Space`; `InputActions.luau:70-74` gives `drift`
keyboard `Space`. Same default priority, neither sinks. The code comment at `:2603-2605`
concedes it — *"InputActions do NOT sink — Space/ButtonX also reach the driving context if
live during the tail; inert there (the kart is finished and frozen between races)"*. That is
a **state assumption, not arbitration**: nothing enforces that the kart is frozen, and the
guard is a race-phase invariant maintained elsewhere.

**DF-3 · gamepad `ButtonX` — `resultsSkip` and `item`, same press.** Identical shape to
DF-2 (`SponsorResults.luau:2620-2622` vs `InputActions.luau:76-80`).

**DF-4 · gamepad `ButtonA` — `drift` and the engine's selection `Activated`.**
`InputActions.luau:70-74` binds `drift` to gamepad `ButtonA`. Several sponsor surfaces
deliberately set `GuiService.SelectedObject` (`SponsorGesture.luau:1853`,
`SponsorRacerList.luau:804`, `SponsorGui.luau:637`), and `SponsorGesture.luau:1760` states
the row activates *"natively when this row is `GuiService.SelectedObject` and A/Enter is
pressed."* One A press therefore fires the row's `Activated` **and** `drift` in the
non-sinking `DriveInputs` context. `FacetSettingsGui` is *not* affected — it uses
`presentModal`, which creates a sinking context at `topModalPriority() + 500` = 3500
(`presenter.luau:2178`), above the un-prioritised `DriveInputs`.

**DF-5 · gamepad `ButtonY` — `cameraToggle` and `sponsorMapToggle`. MITIGATED, fragile.**
`InputBridge.luau:255-268` documents the original defect (two same-priority, non-sinking
contexts both binding `ButtonY`; the engine resolved the tie arbitrarily and re-rolled it on
context churn) and the fix: `camCtx` is disabled outright while sponsoring, so *"at any
instant exactly one context can ever bind ButtonY — no tie to resolve."* The residual: the
mitigation is a **state flag on one of the two contexts**, not arbitration. Any path that
leaves `camCtx` enabled during the sponsor view reopens the tie. Setting explicit
`Priority` + `Sink` on the sponsor context would make it structural.

**DF-6 (systemic, RascalRally) · four `InputContext`s, zero `Priority`, zero `Sink`.**
`DriveInputs` (server, `InputRig.luau:61-93`), `ClientInputs`
(`InputBridge.luau:268-292`), `SponsorInputs` (`SponsorGesture.luau:330-334`),
`ResultsSkipInputs` (`SponsorResults.luau:2609-2613`) all leave both properties at their
engine defaults. §A.2 states no default value for either, and states that equal-priority
contexts *all* receive the input. DF-1 through DF-4 are all instances of this one root
cause. Facet's own comment (`presenter.luau:576-579`) assumes *"a game's own PlayContext"*
sits at priority 2000 — RascalRally has no such number anywhere.

### 4.2 OPEN — Facet

**DF-7 · keyboard `Shift+Return` — `RowActionsMenu` and `Activate`. UNPROVEN EITHER WAY.**
`row_actions.luau:213` binds `Return` with `modifiers = { shift = true }` in a
priority-`10000`, `sink = true` context; the base screen's `Activate` binds plain `Return`
at priority 1500/3500 (`presenter.luau:2251`). The **headless** model
(`actions.luau:341-352` + `:356-380`) filters modifier-mismatched bindings *out of
candidacy before* the sink loop runs, so plain `Return` is sunk only when the modified
binding is eligible. **The engine's behaviour on this exact point is undocumented.** §A.2
describes `Sink` as operating **by KeyCode** — *"the lower priority contexts will not
receive the input signal for `Enum.KeyCode.E`"* — with no statement about whether a
binding's `PrimaryModifier` narrows what the context sinks. Two failure modes, neither
excluded and neither measured:
- (a) the sink is per-binding-candidate → correct today, but nothing proves it;
- (b) the sink is per-KeyCode → **plain `Return` never reaches `Activate` while any
  row-actions context is alive** (Enter stops activating rows), or, if the engine sinks only
  on match but still offers the unmodified sibling, **Shift+Return fires both
  `RowActionsMenu` and `Activate`**.

No gate row records a live-engine measurement of this pair — `gate_manifest.luau:853` pins
only the static DK-16 scan, and the mission notes for this binding
(`row_actions.luau:2180-2210`) reason from the class reference, not from a probe. **This is
the highest-value open input question in the release candidate.**

**DF-8 · Facet `Activate` (`ButtonA`/`Return`/`Space`) and the engine's selection
`Activated`. MITIGATED IN-FRAMEWORK.** `presenter.luau:330-400` collapses cross-source
`{IAS Activate, native `Activated` whose `meta.pointer` is `keyboard` or `gamepad`}` pairs
on the same `path` inside a 0.05 s window, clearing the slot so a third fast press is not
also eaten. Only surfaces that opt into `SelectedObject` mirroring
(`screen_target.luau:2467-2510`) can produce the pair. The hit expander shares
`pointerActivateMeta` since 2026-08-13, so its synthesized activate carries the pointer kind
the collapse keys on. **No open risk inside Facet.** The residual is DF-4: a *consumer* that
mirrors `SelectedObject` itself, outside a Facet surface, gets no collapse.

**DF-9 · `disableLegacyControls()` vs `PlayerScriptsUseInputActionSystem = Enabled` in the
same place — one of the two is dead, and nothing says which.** The gallery and performance
bootstraps call `gamepad_contention.disableLegacyControls()`
(`examples/gallery/client/init.client.luau:156`,
`examples/performance/client/init.client.luau:67`) while the *tracked* project files for
both places declare the flag `Enabled` (INPUT-79/80). The CAS `jumpAction` measurement the
call is built on (`gamepad_contention.luau:17-24`) was taken **2026-07-20, before the flag
was declared**; under the flag the player scripts are IAS contexts, not CAS bindings, so
`legacyStackActive()` should answer `false` and the `UnbindAction("jumpAction")` fallback
should find nothing. No evidence row re-measures either probe in a flag-on place. **This is
the "prior need may be obsolete" recheck the review asked for, and it is unresolved.**
Complicating it: the *built* `Facet-Showcase.rbxl` and the eight tutorial places do **not**
carry the flag (INPUT-82/83), so in exactly those places the CAS repair is still live and
still needed — the two mechanisms are both shipped and each is correct in a different half
of the place matrix.

### 4.3 CHECKED CLEAR (recorded so the next reviewer does not re-open them)

- **`setSecondaryActivate` (`MouseButton2`) vs `Activated`** — `screen_target.luau:2386-2395`
  reasons it out and it holds: a `GuiButton`'s `Activated` fires for the primary button and
  touch only, so the two channels cannot see one press.
- **Pointer capture vs hit expander** — `setPointerHandlers` wires `connectPointerBegan` on
  both the control and its expander (`screen_pointer.luau:397-403`), but the expander is a
  sibling at `z - 1` and a `GuiButton` sinks `InputBegan` to the topmost object only
  (`src/render/renderer.luau:3580`, `src/controls/row_actions.luau:2574`), and
  `beginPointerCapture` refuses a second capture while one is live
  (`screen_pointer.luau:305-331`).
- **`Space` bound to both `Activate` and `GameplayGuard`** — `setKeyboardBound`
  (`presenter.luau:2465-2487`) adds one and removes the other in the same synchronous block;
  no yield between them, so the window in which both exist is not observable.
- **Disclosure long-press raising a plate *and* the row activating on release**
  (`screen_target.luau:2618-2623`) — two responses to one press **by design**, documented:
  *"the plate is a preview, not a capture."* Accepted behaviour, not a defect.

---

## 5. Kept legacy calls and the current impossibility each rests on

Every non-class-1 legacy call that survives, the IAS capability whose absence makes it
necessary **now**, its owner module, and whether an allowlisted adapter already exists.

| Kept call(s) | Missing IAS capability (cited) | Owner module | Adapter status |
|---|---|---|---|
| INPUT-12…17 — `PreferredInput`, four `*Enabled`, `GamepadConnected/Disconnected`, `LastInputTypeChanged`, `OnScreenKeyboard*` | §A.4: *"Device-change observation: Not exposed as its own event… The docs do not document a way to explicitly subscribe to device-change events within IAS itself."* `InputAction.PreferredBinding` is per-action and has no documented change signal. Nothing in IAS reports capability presence, and nothing reports the on-screen keyboard's occlusion rect. | `src/client/roblox_env.luau` | **Exists** — the file header declares it *"the ONE place allowed to read UserInputService/GuiService"*. |
| INPUT-18, 19 — `GuiService` insets, reduced motion, transparency, text size | Not an input surface at all; IAS has no display/accessibility facts. | `src/client/roblox_env.luau` | **Exists** (same adapter). |
| INPUT-11, 26, 59 — `IsKeyDown` ×6 for `shift`/`toggle` | §A.2: `PrimaryModifier`/`SecondaryModifier` gate a **binding**; there is no API to *read* current modifier state. `Traverse` is one Bool action for both directions (Shift+Tab is Tab + a modifier), and list selection semantics (replace/toggle/range) need the modifier at dispatch time, not at bind time. | `src/client/roblox_input.luau` (`system.modifiers`) and its mirror in `src/client/screen_pointer.luau` (`pointerActivateMeta`) | **Two implementations of one fact.** `roblox_input.luau:23-34` and `screen_pointer.luau:102-121` are byte-equivalent six-key reads. Consolidating behind `system.modifiers()` is owed — a second spelling is how the two come to disagree. |
| INPUT-25 — `UserInputService.MouseIcon` | IAS has no cursor concept (§A.2 lists `DisplayImage`/`DisplayName` for *binding glyphs*, not cursors). | `src/client/screen_pointer.luau` | **Exists**. |
| INPUT-29, 30, 34, 38, 42, 43 — pointer capture, `InputBegan`, `UIDragDetector`, hover, press dip | §A.4: *"Pointer position/geometry: Not addressed as a general capability… no mention of hit-testing, screen-to-world conversion, or geometry helpers."* Drag, hover and press-dip are all *per-node geometry* against solved rects. | `src/client/screen_pointer.luau` + `src/client/screen_target.luau` + `src/client/screen_paint.luau` | **Exists** (the ScreenTarget adapter), with a live connection census at `screen_pointer.luau:201-267` that names its own blind spots. |
| INPUT-28 — `GuiService.MenuOpened` | Escape is permanently core-reserved (engine truth D1, `presenter.luau:2413-2416`); IAS cannot bind it, so the only signal that the CoreGui menu took the pointer is this event. | `src/client/screen_pointer.luau` | **Exists**. |
| INPUT-40, 41, 109, 112 — `GuiService.SelectedObject`, `IsFocused`/`CaptureFocus` | §A.4 / research Open risk 4: `SelectedObject` and IAS are *parallel, undocumented-linkage systems*. IAS has no focus concept at all. | `src/client/screen_target.luau` (opt-in per modal); RascalRally: `SponsorGesture`, `FacetSettingsGui` | **Exists in Facet**, opt-in and default-off (`presenter.luau:1689`: non-opted surfaces keep it `nil`). `responder_effects.luau:12-19` records the deliberate deferral of driving it framework-wide. |
| INPUT-44 — `GuiService.TouchControlsEnabled` | IAS cannot hide the mobile touch controls; the alternative (`UserInputService.ModalEnabled`) is deprecated. | `src/client/responder_effects.luau` | **Exists** — a dedicated 85-line module, `pcall`-guarded, restores the prior value on unbind. Carries a standing physical-touch-device rider. |
| INPUT-45, 46 — `GetConnectedGamepads`, gamepad connect/disconnect for haptics | IAS reports nothing about motors or haptic support. | `src/client/haptics.luau` | **Exists**, with an injectable `options.inputService` seam. Honest about its limit: no pad ⇒ `"unknown"`, never `"unsupported"`. |
| INPUT-20…24 — the four CAS/CoreGui probes and `disableLegacyControls` | (a) `Workspace.PlayerScriptsUseInputActionSystem` is **not script-readable on any build** (re-probed `0.734.0.7340915`, 2026-08-15 — `gamepad_contention.luau:31-48`), so every detector must be behavioural; (b) CAS priority and `InputContext.Priority` are **not one arbitration space** (measured live 2026-08-14: a CAS Sink at priority 100 beat an `InputContext` at 10000 with `Sink = true`) — so with the flag off there is no in-framework remedy at all. | `src/client/gamepad_contention.luau` | **Exists**, deliberately **not** exported on the `Facet` table (`docs/guide/07-input.md §7.3`); a consumer requires it directly. **⚠ Recheck owed — see DF-9**: the `jumpAction` probe and unbind were measured before the flag was declared in the example projects, and no evidence re-measures them in a flag-on place. The `traversalKeyContended` (Tab / PlayerList) probe is a genuine documented flag read and stays valid regardless. |
| INPUT-32, 35, 36, 37, 39 — wheel, secondary button, six gestures, text entry, long-press | See §3.2 — five distinct documented IAS gaps (`§A.4` gestures, `§A.4` text entry, `§A.4` pointer geometry, and the absent wheel/mouse-button `KeyCode`). | `src/client/screen_target.luau` (+ `src/input/touch_gestures.luau` for pure normalization) | **Exists**. |
| INPUT-47, 48 — `src/input/actions.luau` + `Facet.newActionSystem` | Not an impossibility — a deliberate ADR-0004 split harness so the presenter runs unchanged headless. | `src/input/actions.luau` | **⚠ Public escape hatch.** `newActionSystem` is exported at `src/init.luau:157` with no guard against a *client* consumer wiring it instead of `roblox_input.newSystem`. Such a client would present a UI that binds nothing to hardware — the failure is silent (no error, no diagnostic). A boot-time warning, or a client-side refusal, is worth adding before release. |
| INPUT-65…72 — runner probes and the VirtualInput driver | The only way to obtain the raw `gameProcessed` second-opinion and to drive keys/pointer headlessly; IAS exposes no input trace. | `examples/gallery/scenarios/runner.luau`, `tools/studio/device_matrix.luau` | **Exists**, test/tool-only, never shipped in `src/`. |
| INPUT-99…101 — RascalRally `InputIdentity` | §A.4 device-change gap. The module's own header explains why even `GetLastInputType()` is unusable on a gamepad+touch handheld (deadzone drift flaps it several times a second) — IAS offers nothing closer. | `src/client/InputIdentity.luau` | **Exists** — the game's single input-identity authority, consumed by `InputBridge`, `SponsorGesture`, `SponsorResults`, `ItemFx`. |
| INPUT-102…104, 106…108, 114, 115 — RascalRally touch/mouse drag geometry | §A.4 pointer-geometry gap; `InputObject.Changed` identity matching (`SponsorGesture.luau:519-550`) exists because a UIS-side identity match *missed on mobile* and latched `_dragActive` forever. | `src/client/InputBridge.luau`, `src/client/SponsorGesture.luau` | **Split across two modules with divergent idioms** — `InputBridge` matches on the UIS event, `SponsorGesture` matches on `InputObject.Changed` after the former was proven lossy. The `InputObject.Changed` idiom is the one that survived a device round; `InputBridge:111-146` still uses the older one. **No single adapter exists; one is owed.** |
| INPUT-110, 111 — `GetImageForKeyCode` | §A.2 `InputBinding.DisplayImage` supplies a *custom* image the developer provides; it does not render the platform's own glyph for a `KeyCode`. `GetImageForKeyCode` is the only source of the correct per-platform button art. | `src/client/SponsorResults.luau`, `src/client/DriverHints.luau` | **Two call sites, no shared owner.** A one-function glyph module is owed (both already `pcall`-guard and both already gate on `InputIdentity`). |
| INPUT-97, 98 — silencing `Player.InputContexts.*` | The IAS player scripts register contexts that **bind gamepad codes even when unused** (`docs/DECISIONS.md:612`: `CharacterContext` owns `Thumbstick1` for on-foot movement this kart game does not have). Nothing in IAS lets a game opt out of the default contexts; disabling them by hand is the only route. | `src/client/init.client.luau:263-310` (+ a duplicate in `MinClient.luau:105-130`) | **Duplicated.** Two copies of the same watcher; the `MinClient` copy is the drift risk. |
| INPUT-113 — `ItemFx.luau:44` | None — **dead import**, zero uses in the file. | — | **Delete.** It is the kind of line that makes a legacy-service allowlist look larger than the real surface. |

---

## 6. Follow-ups, ordered

1. **DF-7** — measure the engine's `PrimaryModifier` × `Sink` interaction for `Shift+Return`
   in a live place. Both failure modes are silent. No artifact exists.
2. **M-1** — convert 6 deprecated `InputAction:Fire()` sites to `Scriptable` `InputBinding`
   + `InputBinding:Fire()`. Mechanical, no behaviour change.
3. **M-3 / INPUT-82…86** — declare `PlayerScriptsUseInputActionSystem` in the two generated
   place projects, the reference-place project, and both RascalRally project files; correct
   the "not rojo-reflectable" claim at `gamepad_contention.luau:26-29`.
4. **DF-6** — give RascalRally's four `InputContext`s explicit `Priority` and `Sink`. This
   closes DF-1 through DF-4 at the root and makes DF-5's mitigation structural.
5. **DF-9** — re-measure `legacyStackActive()` and `cameraKeysContended()` in a place with
   the flag `Enabled`, and record which half of the place matrix each repair still serves.
6. **M-2** — replace `stageButton` with `UIButton` bindings (the engine bug it worked around
   was fixed 2026-04-07).
7. Consolidate the duplicated modifier read (INPUT-11 / INPUT-26), the duplicated
   `InputContexts` silencer (INPUT-97 / INPUT-98), and the two `GetImageForKeyCode` sites;
   delete the dead import at `ItemFx.luau:44`.
8. Guard or document `Facet.newActionSystem` (INPUT-48) against client misuse.
