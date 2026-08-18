# Input-authority wave (R3) — the Studio confirmation check list

For the controller's batched Studio session. Every row is a fact that **cannot** be
established headless, with what to drive, what to read, and the value this wave's
model predicts. Six of the seven rows are confirmations of a change already proved
against the engine-free model; row 5 is the opposite — an **unmeasured** engine
behaviour with two plausible outcomes and a fallback for one of them.

**Two places are involved.** Rows 1–4 and 7 are **Rascal Rally** (open its place;
the sponsor/results overlays and the driving context only exist there). Rows 5 and
6 are **Facet** (`examples/places/Facet-Showcase.rbxl` and one legacy-flag place).

**Build first, both sides.** Every place in this repo was rebuilt on 2026-08-18 to
carry `Workspace.PlayerScriptsUseInputActionSystem = "Enabled"`; Rascal Rally's two
Rojo projects now declare it too. A stale `.rbxl` has the *old* input topology and
will answer every row below wrongly. Confirm the showcase's build stamp against
`git log -1 --format=%h` before reading anything.

**Instrument discipline, from this repo's own scar tissue:**

- **Injected input arrives as `Touch`, not `MouseButton1`.** A check that filters
  on `MouseButton1` manufactures a false positive that agrees with you
  (`docs/lessons/`, and the memory row *roblox input goes to the topmost only*).
- **A `GuiButton` sinks `InputBegan` to the topmost object only.** When reading
  whether a press reached a *background* surface, put the reader on top or read
  the action's state, not a sibling's event.
- **Read the action, not the handler.** `InputAction:GetState()` and a `Pressed`
  counter are the honest instruments; a `print` inside a handler cannot tell you
  that a *second* consumer also fired.
- The four gamepad rows need a **real pad**. `UserInputService:CreateVirtualInput`
  drives keys and pointer, not gamepad buttons, and MCP synthetic keyboard does
  not reach an unfocused Play Solo client at all (Rascal Rally `DECISIONS`,
  2026-07-04).

---

## The counter-instrument every DF row uses

Before driving anything, attach this to the Play session (command bar, client
context). It counts **every** consumer of one press, which is the whole question —
a single `print` in one handler cannot see the second delivery.

```lua
local p = game:GetService("Players").LocalPlayer
local counts, log = {}, {}
local function watch(ctx, label)
    for _, a in ctx:GetChildren() do
        if a:IsA("InputAction") then
            a.Pressed:Connect(function()
                local k = label .. "." .. a.Name
                counts[k] = (counts[k] or 0) + 1
                table.insert(log, k)
            end)
        end
    end
end
watch(p:WaitForChild("DriveInputs"), "drive")
for _, gui in p:WaitForChild("PlayerGui"):GetDescendants() do
    if gui:IsA("InputContext") then watch(gui, gui.Name) end
end
_G.RRINPUT = function() print(table.concat(log, " | ")); table.clear(log) end
```

Call `_G.RRINPUT()` after each single press: it prints **every** action that saw
it. One name = single delivery. Two names = the double-fire is still live.

---

## 1. DF-1 — gamepad **B** while the sponsor table is up

**Drive:** join as a sponsor so the view is `sponsor` (the director's table).
Press **B** once, with nothing armed.

**Read:** `_G.RRINPUT()`, and `DriveInputs.brake:GetState()` immediately after.

**Expect:** exactly `SponsorInputs.sponsorCancel`. `brake` must be `false` and must
NOT appear in the log. Then leave the sponsor view (`view == "driving"`), press B
again, and expect exactly `drive.brake`.

**Model says:** SponsorInputs is priority 3000 `Sink = true`; DriveInputs is 1000.
The engine sinks *by KeyCode* for lower-priority contexts, so `brake` is never
offered the press. If `brake` still fires, the engine's Sink is narrower than its
own class reference states and the whole band scheme needs re-derivation —
report the reading, do not patch around it.

## 2. DF-2 / DF-3 — keyboard **Space** and gamepad **X** during the results tail

**Drive:** finish a race and, while the skip chip is visible (the skip-enabled
phase), press **Space** once; then **X** once.

**Read:** `_G.RRINPUT()` after each, plus `DriveInputs.drift:GetState()` /
`DriveInputs.item:GetState()`.

**Expect:** exactly `ResultsSkipInputs.resultsSkip` for each. Neither `drift` nor
`item` may appear or read `true`.

**Then the negative half, which matters as much:** wait until the skip chip is
gone (`ResultsSkipInputs.Enabled == false`), press Space and X again while driving,
and expect exactly `drive.drift` and `drive.item`. A sink that outlives its
surface is a permanently deaf game, and this is the row that would catch it.

## 3. DF-4 — gamepad **A** on a selected sponsor row (**the undocumented one**)

This is the row with a real chance of a surprise. The other consumer of A on a
sponsor surface is a **native `GuiButton.Activated`** fired because the row is
`GuiService.SelectedObject` — that is not an `InputContext`, so no priority can
arbitrate it. The wave's close is a **no-op `sponsorActivateGuard`** claiming A
inside the sinking overlay, which removes the half that *can* be arbitrated.

**Drive:** in the sponsor view, navigate the racer list with the D-pad until a row
is selected (`GuiService.SelectedObject ~= nil`), then press **A** once.

**Read:** `_G.RRINPUT()`, `DriveInputs.drift:GetState()`, and **whether the row
actually activated** (the card arms / the racer is picked — the visible outcome).

**Expect (the intended result):** `SponsorInputs.sponsorActivateGuard` in the log,
`drift == false`, **and the row still activates**.

**The failure mode to look for:** the row does **not** activate. That would mean an
IAS sink also starves the engine's native selection activation — undocumented
either way. If that happens, record it here and rebind the guard to something that
is not the activation key, or drop the guard and accept DF-4 as a mitigated-only
residual; do **not** leave a sponsor surface whose rows cannot be pressed.

Also check the results screen the same way: with the results CTA selected, press A
and confirm the CTA still confirms.

## 4. DF-5 — gamepad **Y**, with the camera context deliberately left ON

**Drive:** enter the sponsor view, then in the command bar force
`InputBridge`'s context back on:
`game:GetService("Players").LocalPlayer.PlayerGui.TouchControls.ClientInputs.Enabled = true`.
Press **Y** once.

**Read:** `_G.RRINPUT()`.

**Expect:** exactly `SponsorInputs.sponsorMapToggle`. The camera must not toggle.
This is the row that proves the 2026-07-04 mitigation is now a belt and the bands
are the arbitration — before this wave, that forced-on state re-opened the tie.

## 5. **DF-7 — `PrimaryModifier` × `Sink`. UNMEASURED. Both outcomes are live.**

Facet's `row_actions` binds **Shift+Return** to `RowActionsMenu` in a
priority-`10000`, `Sink = true` context, while the base screen binds **plain
Return** to `Activate` at 1500/3500. The engine documents `Sink` as operating **by
KeyCode** — *"the lower priority contexts will not receive the input signal for
`Enum.KeyCode.E`"* — and says nothing about whether a binding's `PrimaryModifier`
narrows what the context sinks. **No binding was changed this wave**; this row is
the measurement that decides whether one is needed.

**Place:** `examples/places/Facet-Showcase.rbxl`, a **real keyboard**, the demo
with a Table that has row actions mounted (so a row-actions context is alive).

**Drive and read, in this order — the order matters:**

1. With **no** row focused (no row-actions context mounted): press **Return** on a
   plain button. Confirm it activates. *(Control reading — proves the keyboard is
   reaching the place at all.)*
2. Focus a row so the row-actions context mounts. Confirm it is alive:
   `#game:GetService("Players").LocalPlayer.PlayerScripts:GetDescendants()` is not
   the instrument — instead read the context by name in the Facet debug dump, or
   simply confirm the row's action affordance is present.
3. **Press plain Return** (no shift) on the focused row.
   **Read:** did the row ACTIVATE?
4. **Press Shift+Return** on the same row.
   **Read:** did the row-actions MENU open, and did the row **also** activate?

**The three possible results, and what each means:**

| # | plain Return (step 3) | Shift+Return (step 4) | verdict |
|---|---|---|---|
| **a** | row activates | menu only | **sink is per-binding-candidate.** Correct today; no change needed. Record the reading and close the row. |
| **b** | row does NOT activate | menu only | **sink is per-KeyCode.** Enter stops activating rows for as long as any row-actions context is alive — a silent, serious regression. **Fallback: rebind the menu to a distinct chord** that shares no KeyCode with `Activate` (the inventory suggests this explicitly; `ButtonX` already covers the pad, so the keyboard chord is the only thing that moves). |
| **c** | row activates | menu **and** row activate | **the engine sinks only on match but still offers the unmodified sibling.** Double-fire on Shift+Return. Same fallback as (b). |

**Record the reading verbatim** into
`artifacts/release-candidate-review/input/df7-measurement.md` — that file is the
evidence for the bare-PENDING gate row `df7-modifier-sink-measured`, which cannot
pass until it holds a real reading.

## 6. DF-9 — `disableLegacyControls()` is inert under the flag

**Drive:** open `examples/places/Facet-Showcase.rbxl` (flag **on**), Play, then in
the client command bar:

```lua
local gc = require(game:GetService("ReplicatedStorage").Facet.client.gamepad_contention)
print(gc.iasPlayerScriptsActive())          -- expect: true
print(gc.disableLegacyControls())            -- expect: true   inert: IAS owns PlayerScripts
print(gc.legacyStackActive())                -- expect: false  (no CAS jumpAction under IAS)
print(gc.cameraKeysContended())              -- READ AND RECORD — see below
```

**Expect:** `iasPlayerScriptsActive()` `true`; `disableLegacyControls()` returns
`true, "inert: IAS owns PlayerScripts"` and **returns immediately** (no 5-second
`PlayerModule` wait); `legacyStackActive()` `false`.

`cameraKeysContended()` is the open reading: under the flag the camera's keys
should have left `ContextActionService` entirely, so **`false` is expected** — but
it was `true` in a flag-off session on 2026-08-15 and no evidence row has ever
re-measured it in a flag-on place. Record whichever it is.

**Then the other half of the place matrix.** Open one of the eight tutorial places
built **before** today (`git stash` is not needed — any pre-2026-08-18 `.rbxl` you
still have), or temporarily build one with the property removed, and confirm
`iasPlayerScriptsActive()` is `false` and `disableLegacyControls()` still returns
`true, "disabled"`. The point of the row is that the two mechanisms each serve a
different half of the matrix, and neither has been retired.

## 7. The two relays the migrations depend on (Rascal Rally)

Both migrations replaced a call that was **proven working** with one that is
documented but unproven **for Server Authority**, and no headless model can tell
the difference. If either fails, driving breaks on touch or the assists die.

**7a — `InputBinding:Fire` on a server-created action reaches the server.**
Drive on touch (or in the emulator) and drag to steer. Then, on the **server**:

```lua
local ctx = game:GetService("Players"):GetPlayers()[1].DriveInputs
print(ctx.steerTouch:GetState(), ctx.brakeStick:GetState(), ctx.throttleStick:GetState())
```

**Expect:** `steerTouch` tracks the drag (non-zero while dragging, back to 0 on
release) as read **on the server**. If it reads 0 server-side while the client's
own read is right, the Scriptable-binding write does not relay and the migration
must go back to `InputAction:Fire` with the deprecation accepted.

**7b — `InputBinding.UIButton` on a server-created action reaches the server.**
Tap and hold the on-screen **DRIFT** button, then the **ITEM** button. Read
`ctx.drift:GetState()` / `ctx.item:GetState()` **on the server** while held, and
again after release.

**Expect:** `true` while held, `false` after release. **And the drag-off case that
the deleted hand-staging existed for:** press DRIFT, slide the finger **off** the
button, lift. `drift` must return to `false`. (Staff fix 2026-04-07: *"the Released
event will now fire"*. This is the row that confirms it on the device this game
actually ships to.)

Also confirm the buttons still do not take pad focus: with a gamepad connected the
touch cluster is hidden entirely (`InputIdentity` gates it), and `Selectable` stays
`false` on every button.
