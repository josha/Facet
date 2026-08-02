# TextBox — verified engine facts (2026-07-20)

Live probes for the LuauUI `UI.TextInput` expansion. Every row was run against
a **real** Roblox Studio TextBox in `Place1.rbxl` (LuauUI gallery place) over the
Studio MCP — reflection/property probes in the **Edit** datamodel, focus/typing
probes in a running **Play → Client** VM. No claim below is from memory or docs
prose unless explicitly marked UNVERIFIED-ON-DEVICE / API-documented-but-unprobed.
Machine-readable mirror: `artifacts/studio/expansion-textinput-probe.json`.

Status legend: **PROBED** = observed live here; **UNVERIFIED-ON-DEVICE** = the
Studio-observable half is probed, the device/mobile half cannot be reproduced in
desktop Studio; **API-DOC-UNPROBED** = official engine behavior, not scriptably
isolable here.

---

## 1. Reflection / capability (Edit datamodel)

Probe: `Instance.new("TextBox")`, `pcall` read each property; `Enum.TextInputType:GetEnumItems()`.

| Property | Exists? | Note |
|---|---|---|
| `TextInputType` | **YES — but SECURITY-LOCKED** | read AND write both `pcall`-fail with `"The current thread cannot read/write 'TextInputType' (lacking capability RobloxScript)"`. The member is real; it is gated to CoreScript/RobloxScript security. **Game and plugin scripts cannot get or set it.** |
| `TextEditable` | yes | default `true` |
| `ClearTextOnFocus` | yes | default `true` |
| `MultiLine` | yes | default `false` |
| `PlaceholderText` | yes | |
| `PlaceholderColor3` | yes | |
| `CursorPosition` | yes | default `1` |
| `SelectionStart` | yes | default `-1` (no selection) |
| `ContentText` | yes | default mirrors `Text` (both `"TextBox"` on a fresh instance) |
| `ShowNativeInput` | yes | default `true` |
| `Text`, `RichText`, `TextWrapped`, `AutomaticSize`, `TextBounds` | yes | |

`Enum.TextInputType` values (11): `Default=0, NoSuggestions=1, Number=2, Email=3,
Phone=4, Password=5, PasswordShown=6, Username=7, OneTimePassword=8,
NewPassword=9, NewPasswordShown=10`. **The enum exists and is usable; the property
that would consume it is not reachable from our security context.**

IME / autocorrect surface: none discoverable. `IMEBehavior`, `ImeBehavior`,
`AutocorrectBehavior`, `SuggestionBehavior`, `EnableTypingIndicator`,
`OnScreenKeyboardInput` all `pcall`-fail as non-members (not security-locked —
absent). The only text-mode knob is the security-locked `TextInputType`.

**Load-bearing:** LuauUI **cannot** drive keyboard mode (numeric/email/password)
via `TextInputType` from a game/plugin script. `Password`-style masking and
numeric keypads are not available to us through this property. Treat the whole
`TextInputType` axis as unavailable; do not design an API that promises it.

Probe code (representative):
```lua
local tb = Instance.new("TextBox")
local ok, err = pcall(function() return tb.TextInputType end)
-- ok=false, err="...lacking capability RobloxScript"
local okw, errw = pcall(function() tb.TextInputType = Enum.TextInputType.Number end)
-- okw=false, errw="...lacking capability RobloxScript"
```

## 2. Focus lifecycle (Play → Client)

Probe: `CaptureFocus` / `IsFocused` / `GetFocusedTextBox` / `ReleaseFocus`, and a
`FocusLost` connection driven by `ReleaseFocus(submitted)`.

- **CaptureFocus round-trip is fully scriptable.** Before: `IsFocused()==false`,
  `UIS:GetFocusedTextBox()==nil`. After `tb:CaptureFocus()`: `IsFocused()==true`
  **and** `UIS:GetFocusedTextBox()==tb`. After `tb:ReleaseFocus()`: both clear
  (`false` / `nil`). — PROBED.
- **`FocusLost(enterPressed, inputThatCausedFocusLost)` semantics** via
  `ReleaseFocus`: `ReleaseFocus(true)` → `enterPressed=true`; `ReleaseFocus(false)`
  and `ReleaseFocus()` (no arg) → `enterPressed=false`. The `input` InputObject
  arg is **`nil` for programmatic releases** (it only carries a real InputObject
  when an actual key/click caused the loss). — PROBED.
- **Return-produces-enterPressed / Escape-releases / MultiLine-Return-inserts-
  newline:** these depend on a *real* keypress into a focused box. Injected
  keystrokes reach `UserInputService` but are **not fed into the TextBox
  character/submit buffer** (see §3), so Return/Escape submit-vs-newline behavior
  is **API-DOC-UNPROBED** here. Official behavior: single-line Return fires
  `FocusLost(enterPressed=true)`; `MultiLine=true` Return inserts `\n` and does
  NOT submit; Escape fires `FocusLost(enterPressed=false)`. The scriptable
  equivalent — `ReleaseFocus(true)` for submit — is proven above and is what the
  adapter should use.

## 3. THE HANDSHAKE FACT (Play → Client) — critical

Probe: install `UIS.InputBegan` listener counting keyboard events by
`gameProcessedEvent`; click the box via real mouse to focus it; inject `H`, `I`,
`Left` via `user_keyboard_input`; read counters + `Text` + `GetFocusedTextBox`.

- **With the box focused (`IsFocused()==true`, `GetFocusedTextBox()==box`), every
  injected keyboard input reached `UIS.InputBegan` with `gameProcessedEvent ==
  true`** — 3 of 3 keys, zero with `false`. — **PROBED.**
- **This is the handshake LuauUI relies on:** while a TextBox owns focus the
  engine marks keyboard InputBegan as game-processed, so any LuauUI semantic
  action that (correctly) ignores `gameProcessedEvent==true` input will **not
  fire** — letters and arrows are consumed by the focused box, not by nav/hotkey
  bindings. `UIS:GetFocusedTextBox()` is the reliable "is a box eating keys right
  now" query and returns the exact box.
- **Injected keys do NOT type into the box.** After H/I/Left with the box focused,
  `Text` stayed `""` and `GetPropertyChangedSignal("Text")` fired 0 times. The
  MCP keyboard injection delivers InputObjects (which is why InputBegan sees them,
  gp=true) but does not reach the engine's lower-level character-insertion path.
  **Real text entry cannot be driven headlessly** — needs a human at the keyboard.
- **Clean negative control (unfocused box → gp=false) could not be isolated.**
  Injected keyboard delivery is coupled to game-viewport focus, and every
  `execute_luau` steals viewport focus; only the box-targeted mouse click
  reliably re-granted it (which also focuses the box). Attempts to inject while
  unfocused delivered **0** InputBegan events (viewport unfocused), so the
  contrast is confounded, not contradicted. The positive result is consistent
  with documented engine behavior (focus ⇒ gameProcessedEvent on keyboard).
  Marked **PARTIALLY-PROBED** (positive PROBED, negative UNVERIFIED — injection
  limitation, matches `docs/lessons/engine-input-truths-phaseb.md` #5).

## 4. Live text change & cursor-on-rewrite (Play → Client)

- **`GetPropertyChangedSignal("Text")` fires on a programmatic `tb.Text = ...`
  assignment** (fired exactly once per set). — PROBED. So the adapter can observe
  its own writes; for max-length clamping it must guard re-entrancy.
- **`ContentText == Text` when `RichText=false`** (probed equal). ContentText
  strips rich-text tags; with RichText off they are identical.
- **Cursor behavior when `Text` is rewritten from code while focused** (the
  max-length clamp case): the cursor **auto-clamps to the end of the new text**,
  it does **not** reset to 1 and does **not** need manual repositioning:
  - focused, `Text` len 6, `CursorPosition=7`; rewrite `Text="abc"` → `CursorPosition==4` (len+1 of "abc").
  - rewrite longer `Text="abcdefghij"` → cursor **stays 4** (no jump to end).
  - `CursorPosition=5`, rewrite `Text="ab"` → `CursorPosition==3` (len+1 of "ab").
  — PROBED. **Load-bearing:** a max-length clamp that truncates `Text` on change
  leaves the caret sensibly at the truncated end automatically; only set
  `CursorPosition` explicitly if you want a *different* caret than "current index,
  clamped to the new length".

## 5. Layout truths (Play → Client, real render)

- **Single-line, `TextWrapped=false`, small rect (120×32), long text:**
  `TextBounds.X==626` ≫ `AbsoluteSize.X==120`, `TextFits==false`. Text overflows;
  `TextBounds` reports the **full unwrapped extent**. When focused the engine
  scrolls the visible window to follow the caret (documented; the numeric proof
  here is the overflowing TextBounds). — PROBED.
- **`TextWrapped=true` + `MultiLine=true`, fixed rect (120×80):** `TextBounds ==
  {120, 54}` — X clamped to the rect width, Y spans multiple lines. **Wrapping
  works at rest in Studio.** — PROBED. (`TextFits==false` because the wrapped block
  plus a long token still doesn't fully fit; wrapping itself is confirmed by
  X-clamp + multi-line Y.)
- **Wrap-while-*typing* mobile defect (devforum 1014598):** cannot reproduce
  mobile IME in desktop Studio. The at-rest wrap above is the Studio-observable
  half; the type-time-on-mobile breakage is **UNVERIFIED-ON-DEVICE**.
- **`AutomaticSize=Y`, `MultiLine`+`TextWrapped`:** box grew from `AbsoluteSize.Y
  27 → 162` when a longer string was assigned. **AutomaticSize.Y grows the box as
  text content changes.** — PROBED for `SetText`. Grow-*while-typing* uses the same
  content→size path but real keystroke typing is UNVERIFIED-ON-DEVICE (see §3).
- **TextBox inside a `ClipsDescendants=true` host (Table-cell condition):** host
  80px wide, cell TextBox 200px wide (`AbsoluteSize.X 200 > host 80`). The host
  clips (`ClipsDescendants==true`); **focus still works inside the clip** —
  `CaptureFocus()` → `IsFocused()==true` and `GetFocusedTextBox()==cell`. — PROBED.
  Clipping crops the overflow visually (engine-standard) and does not interfere
  with focus.

## 6. TextSize / TextBounds (Play → Client)

- **`TextBounds` updates on `SetText`** and
  **`GetPropertyChangedSignal("TextBounds")` fires** on the change (fired once;
  `TextBounds` went to `{175.5, 30}` for the new string). — PROBED. Usable as the
  grow-as-you-type signal for autosizing / caret-follow math.

## 7. On-screen keyboard occlusion (Play → Client, desktop)

- `UIS.OnScreenKeyboardVisible == false`, `OnScreenKeyboardPosition == {0,0}`,
  `OnScreenKeyboardSize == {0,0}` — **and they stay that way while a TextBox is
  focused** (`OnScreenKeyboardVisible_whileFocused == false`). Environment flags:
  `TouchEnabled=false`, `KeyboardEnabled=true`, `GamepadEnabled=true`. — PROBED.
  **The on-screen keyboard never appears on desktop Studio**, so occlusion is a
  no-op there.
- The env feed **`src/client/roblox_env.luau`** consumes exactly these APIs:
  guarded by `UserInputService.OnScreenKeyboardVisible`, it watches the
  `OnScreenKeyboardPosition` changed signal and, when visible, sets
  `keyboardOcclusionRect = {x=pos.X, y=pos.Y, w=size.X, h=size.Y}` (else `nil`).
  On desktop that rect stays **nil** — confirmed consistent with the probe.
- The device emulator cannot summon the real OS keyboard, so **actual keyboard
  occlusion geometry on a touch device is UNVERIFIED-ON-DEVICE** (needs a
  physical phone/tablet). The env plumbing that would consume it is verified.

## 8. Gamepad story (Play → Client)

- **`TextBox.Selectable` defaults `true`.** — PROBED.
- **`GuiService.SelectedObject = tb` is settable** (`selectedObjectIsBox==true`)
  and **selection alone does NOT focus** the box (`IsFocused()==false` right after
  select). `GuiService.AutoSelectGuiEnabled==true`. — PROBED.
- **ButtonA-on-a-selected-TextBox → native `CaptureFocus`:** this is the engine's
  default gamepad selection behavior (pressing the primary/A button on a selected,
  focusable TextBox captures focus). It could not be cleanly injected here —
  gamepad-button injection is coupled to viewport focus (same limitation as §3),
  and forcing viewport focus via a click would itself focus the box and confound
  the test. Marked **API-DOC-UNPROBED** (engine default). The scriptable
  precondition — SelectedObject settable, selection≠focus — is PROBED, so the
  adapter can rely on setting `SelectedObject` and letting the engine's A-press
  drive `CaptureFocus`, or call `CaptureFocus` itself on the gamepad activate.

---

## Summary of load-bearing facts

1. **`TextInputType` is real but RobloxScript-security-locked** → unavailable to
   game/plugin scripts. No numeric/email/password keyboard mode via this API. No
   other IME/autocorrect member exists.
2. **Focus is fully scriptable** (`CaptureFocus`/`IsFocused`/`GetFocusedTextBox`/
   `ReleaseFocus`); `ReleaseFocus(true/false)` drives `FocusLost(enterPressed)`.
3. **Handshake PROBED:** focused box ⇒ keyboard `InputBegan` arrives with
   `gameProcessedEvent==true`; `GetFocusedTextBox()` names the box. Semantic
   actions that skip game-processed input won't fire while typing.
4. **Cursor auto-clamps to the end of a code-truncated `Text`** while focused (not
   reset to 1); `GetPropertyChangedSignal("Text")` fires on programmatic set.
5. **Wrapping works at rest**, single-line overflows (full-extent `TextBounds`),
   `AutomaticSize.Y` grows on `SetText`, and focus works inside a
   `ClipsDescendants` host.
6. **Desktop has no on-screen keyboard**; the env feed's `keyboardOcclusionRect`
   is correctly nil there. Mobile occlusion + wrap-while-typing + real typing +
   ButtonA native capture are the device-only riders.
