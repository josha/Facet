# Review packet — `desktop-keyboard-navigation` (roadmap Step 8)

Every automatable row has been driven. The gate block re-runs at final source with
twelve of its fourteen checks PASS; the two that do not are this packet's own
subject (`physical-and-contended-rows`, declared FAIL_ENVIRONMENT and
non-release-blocking) and `fresh-context-reviews`, which clears when the three
reviewer verdicts land. The behavior is implemented and headlessly verified at E1,
and Studio verified at E3 in both the gallery place and Rascal Rally's own place.
Four rows remain that no instrument in this build can close.

Each has one exact procedure below; none needs you to discover the test case,
assemble game state, or read a log. Two of the four are not awaiting automation
anyone could write: DK17-A and DK17-F are awaiting a physical press or a change in
Roblox, and no further work here closes them.

**Build under test:** LuauUI `0.8.0`, source stamp `2ea5cb0b-2890577`.
**Entry point:** open the LuauUI gallery place, set the workspace attribute
`LuauUI_Scenario = "keyboard_navigation"`, press Play. The fixture is one screen
carrying a text field, a two-button row, a slider, a stepper and a scrolling
list, plus a modal on demand. It presents with **zero** input options.

**Reset between runs:** `workspace.LuauUIScenarioAPI.reset:Invoke()`.
**Export:** `workspace.LuauUIScenarioAPI.report:Invoke()` returns the whole
trace (raw keys, semantic actions, focus log, scroll, state, responder,
lifecycle) as JSON. Save it beside your result.

---

## Row DK-P1 — a real operating-system keyboard on a phone or tablet

**Why it cannot be closed here:** the Studio device emulator never summons the
mobile OS keyboard, and it cannot produce a keyboard-capable touch profile at all
(`preferredInput = Touch` is unreachable from the emulator —
`docs/lessons/`). Everything below was proven on a desktop profile.

**Procedure**
1. Join the gallery place from a **physical** tablet or phone with a hardware
   keyboard attached (a keyboard case or a Bluetooth keyboard).
2. Confirm the environment sees both classes: run
   `report:Invoke()` and check `env.capabilities` reports `touch = true` **and**
   `keyboard = true`, and `derived.interactionClasses` lists both.
3. Press **Tab** several times. Expected: the focus ring walks the same order it
   walks on desktop, and touch still works — tapping a control still activates
   it and still moves focus without drawing a ring.
4. Press **Space** on a focused button. Expected: it activates once.
5. Focus the slider's track and press **Left/Right**. Expected: the value moves
   by one step per press and focus does not move.

**Judgment requested:** does a keyboard-capable touch device behave like a
desktop for these three conventions, with touch unaffected? Yes/no plus the
exported trace.

---

## Row DK-P2 — physical keyboard hot-plug against a real avatar control stack

**Why it cannot be closed here:** the hot-plug row was driven by writing the
`capabilities` environment fact, which proves the framework's response (bindings
created and destroyed, no stuck sink) but not the engine's own capability
transition against real player scripts.

**Procedure**
1. Join **Rascal Rally** (not the gallery) on a desktop client, with
   `Workspace.PlayerScriptsUseInputActionSystem` ticked.
2. While driving, confirm the HUD is passive: press **Space** and **Tab**.
   Expected: the kart behaves exactly as it always has; the HUD's focus does not
   move.
3. Maximize the sponsor table so the HUD engages. Press **Space**. Expected: the
   focused control activates and the avatar does **not** jump.
4. Resign (Cancel / tap outside). Press **Space** again. Expected: gameplay has
   it back, exactly.
5. Reach the results screen as a **racer** and press **Space**. Expected: the
   celebration skips, and **no** results button activates. (This is the
   collision DKN-4 fixed; it is the single most important row here.)
6. Unplug and replug a USB keyboard mid-session and repeat step 3.

**Judgment requested:** is avatar input untouched while passive, and is exactly
one thing happening per press while engaged?

---

## Row DK17-A — Tab while the CoreGui players list is enabled

**Why it cannot be closed here:** with the players list enabled (the default) the
engine refuses to synthesize `Tab` at all — `VirtualInput::SendKey` throws *"key
is permanently bound to a CoreGUI core action"*, the same refusal it gives for
`Escape`. There is no second scriptable path
(`VirtualInputManager:SendKeyEvent` needs RobloxScript capability). Full evidence
and the decision in `decisions.md` § DKN-1.

**Procedure**
1. Join the gallery place. Do **not** disable the players list.
2. Confirm the probe agrees:
   `require(ReplicatedStorage.LuauUI.client.gamepad_contention).traversalKeyContended()`
   should return `true`.
3. Press a **physical** Tab. Record: does the players list toggle? Does the focus
   ring move? Run `report:Invoke()` and check whether any `Traverse` action
   appears in `custom.actions` and whether the raw key arrives with
   `gameProcessed = true`.
4. Run `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)`, then
   press physical Tab again and repeat the reading.

**Judgment requested:** the exact answer to "does a physical Tab reach a
developer `InputContext` while the players list is enabled?" Roblox's
documentation says it should not; nothing in this build could test it. If it
*does*, DKN-1's limitation paragraph should be softened. If it does not, the
documented remedy is already shipped and nothing changes.

---

## Row DK17-F — Tab inside a focused TextBox

**Why it cannot be closed here:** measured live, while a `TextBox` holds engine
keyboard focus Roblox marks keyboard input `gameProcessed = true` and **no**
developer IAS keyboard binding fires — so the framework's `handleTraverse` seam
cannot be reached. The control row one call later on the same key proves the
instrument works. Roblox staff have the suppression on record (DevForum 4100260).
Decision in `decisions.md` § DKN-2.

**Procedure**
1. In the gallery fixture, press Return on the focused field to begin editing.
2. Press a **physical** Tab. Record all four: does a tab character appear in the
   field? Does the edit end? Does `custom.state.commits` increment? Does focus
   advance?
3. Expected on today's engine: nothing at all happens (no tab character, no
   commit, no advance) — which satisfies the framework's three safety
   requirements and fails the convenience one.
4. Re-run this row **if** Roblox ever lifts the keyboard-binding suppression.
   Nothing first-party promises it will — the change scheduled in DevForum 4100260
   moves the *mouse* side to match the keyboard side, not the reverse. If the key
   does start arriving, the headless behavior
   (commit through validation, then advance) engages with **no code change** and
   this row flips to `PASS_AUTOMATED`.

**Judgment requested:** none — this is a re-measurement, not an opinion.

---

## What is already closed, so you do not re-test it

Driven with real `VirtualInput` key events through the real adapter in a visible
Play session, each paired with raw-input, semantic-action, focus, scroll, state,
responder and lifecycle traces (`studio/keyboard.json`):

- Tab / Shift+Tab traversal, one press = one move, reproduced three times;
- traversal across group boundaries and into a scrolling list, with the host's
  own `CanvasPosition` moving 0 → 102;
- a modal trapping Tab and restoring the prior focus exactly on dismiss;
- Space **and** Return each activating once per press;
- a focused Slider consuming Left/Right on a **grouped** screen while the
  vertical axis still navigates off it;
- the Adjust keys bound only while focus sits on a declared target;
- keyboard hot-plug adding and removing the real `InputBinding` instances with no
  stuck sink.
