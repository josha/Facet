# ADR-0057 — Gamepad d-pad auto-repeat

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0057. Additive — no ADR-0040 row (no required-prop flip, no
documented-default value change on any existing option; a held gamepad
direction previously produced one focus move and now produces a bounded
sequence of the SAME move, through the SAME call, which is a bug fix on an
existing verb rather than a changed contract).
**Home:** `src/input/actions.luau` (`isGamepadKeyCode`, `binding.isGamepad`,
`action.lastGamepad`, `action._deliver`'s second parameter),
`src/present/presenter.luau` (`bindDpadRepeat`, wired onto `Navigate` and
`NavigateH`; the `suspendAxisKeys` fix below).
**Guards:** `tests/dpad_repeat.spec.luau`.

## Context

Director's goal-prompt item 4, verbatim: "Gamepad: holding d-pad doesn't
repeat/advance selection. Framework should auto-repeat."

**What the platform actually provides — verified against current docs, not
memory (ENGINEERING.md "platform-native first").**

- The [Input Action System](https://create.roblox.com/docs/input/input-action-system)
  — `InputAction`/`InputContext`/`InputBinding`, the ONLY input layer Facet
  uses (`docs/reference/api.md` "Input" §, ADR-0004) — documents exactly three
  events on an `InputAction`: `Pressed` (false→true transition), `Released`
  (true→false), and `StateChanged` (any change). No `Repeat`, `RepeatRate`, or
  `RepeatDelay` property exists anywhere in that surface, and none is
  documented for a HELD button. This matches Facet's own headless model
  exactly (`action.state` changes on transition only, per `_deliver`'s dedup
  guard) — the mirror is faithful; the platform genuinely does not repeat
  device input.
- [`GuiService`](https://create.roblox.com/docs/reference/engine/classes/GuiService)
  and its native gamepad selection navigator (`SelectedObject`,
  `GuiNavigationEnabled`) DO visibly auto-repeat when a player holds a d-pad
  direction on a native (CoreGui-driven) selectable UI — this is the observed
  behavior the director's bug report is implicitly comparing Facet to. Its
  timing is internal engine C++ and is not exposed through any scriptable
  property, event, or documented constant; nothing in the current reference
  pages or the gamepad input guide states a number. So Facet cannot read the
  engine's own repeat cadence and match it exactly — there is nothing to
  delegate to and nothing to measure without a physical device instrumented
  at the frame level (device-owed, see below).
- **Why Facet's own focus advance didn't inherit this "for free":** Facet's
  focus navigation is NOT native GuiObject selection — it is Facet's own
  `focus_graph` driven by the Input Action System's `Navigate`/`NavigateH`
  `Direction1D` actions (`docs/reference/api.md` "Focus" §). A `Direction1D`
  action delivers its bound `direction` value once on key-down and returns to
  `0` on key-up, exactly like `Pressed`/`Released` — there is no path by which
  holding a key could produce more than one delivery, because the ENGINE
  itself does not repeat the underlying `InputBegan` for a held key any more
  than it does for a held gamepad button feeding a scripted `InputAction`.
  CoreGui's own repeat is a completely separate, internal mechanism bolted
  onto native selection specifically, not a general engine behavior any
  `InputAction` consumer inherits.

**Conclusion: there is nothing to delegate to.** Auto-repeat has to be
implemented in the framework, at the presenter, because nothing beneath it
provides one.

## Decision

### Timing: 0.4s initial delay, 0.1s steady repeat

Roblox does not document its own native repeat cadence anywhere reachable
(above), so the "measure Roblox's own defaults" branch of the director's
instruction is unavailable without physical-device frame-level
instrumentation (device-owed). Falling back to the instruction's own
alternative: the console-standard shape (~400ms initial, ~100ms steady). This
also matches an EXISTING precedent already shipped in this codebase —
`screen_target.luau`'s `DISCLOSE_LONG_PRESS_S = 0.4` — so the framework is
internally consistent about what "long enough to mean it" is, rather than
inventing a second unrelated number for a second held-input feature.

### Mechanism: presenter-level, scope-owned, driven by the existing tick clock

`bindDpadRepeat(action, fire)` in `presenter.luau` wraps `Navigate` and (when
present) `NavigateH`:

- Observes `action.state` for the held direction (only while
  `action.lastGamepad` — see below); tracks elapsed time since the last fire.
- Drains owed repeats through the presenter's OWN existing frame clock
  (`self.onTick`, the same idiom the drag-to-edge autoscroll stepper already
  uses) — no `task.delay`/`task.wait`/wall clock anywhere. A slow first frame
  that owes several intervals fires all of them in that one tick rather than
  losing them (a `while` drain, not an `if`).
- Fires through the EXACT SAME `navigateVertical`/`navigateHorizontal`
  functions a fresh press already calls, so wrap rules, `navigateIntercept`,
  and the armed-aim sync apply per repeated step exactly as they do to a
  single press. Nothing about the ring's own rules is reimplemented.
- `scope:own`'d with everything else the SURFACE owns — the repeat timer is
  torn down the instant the surface dismisses, not the process.
- Scoped to `Navigate`/`NavigateH` only. `Adjust`/`AdjustAxis` (a
  slider/stepper's held-repeat) is a separate, un-asked-for UX call — the
  director's item says "advance selection," not "adjust a value" — and is
  deliberately out of scope for this round.

### Gating: gamepad-only, at the source

The director's item is specifically about the gamepad; a keyboard arrow held
down must keep its existing single-step behavior. `Navigate`/`NavigateH` are
shared actions bound by BOTH keyboard keyCodes (`Up`/`Down`/`Left`/`Right`) and
gamepad ones (`DPadUp`/`DPadDown`/`DPadLeft`/`DPadRight`, plus the
`Thumbstick1`-as-d-pad axis tolerance), so the repeat gate cannot key off the
ACTION — it has to know which BINDING delivered the currently-held value.

`actions.luau` now stamps this at the one place that already knows: every
Roblox gamepad `KeyCode` is named `ButtonX`/`DPad*`/`Thumbstick*` —
exclusively; no keyboard `KeyCode` shares any of the three prefixes (the
engine's own `Enum.KeyCode` naming convention, not a guess). `binding.isGamepad`
is computed once per binding from that name (an axis binding — always a
`Thumbstick*` in this vocabulary, there being no non-gamepad concept of an
analog axis here — is unconditionally gamepad-classed). `action._deliver` now
takes an optional second parameter and stamps `action.lastGamepad` from it
immediately before the value change lands; a deduped re-delivery of the same
value never reaches that line, so the field cannot go stale between one real
change and the next. The presenter's repeat glue reads `action.lastGamepad`
at the moment its `core:observe(action.state, …)` callback fires.

Rejected alternative: gate on the environment's derived `effectiveInput`
("Gamepad"/"Touch"/"KeyboardAndMouse") instead of the delivering binding. That
signal answers "what did the player use MOST RECENTLY across the whole
session," not "what produced THIS value" — it is a platform fact updated on
its own schedule (`UserInputService.PreferredInput`), not guaranteed to have
already flipped to "Gamepad" by the time the very FIRST d-pad press of a fresh
session delivers its `Navigate` value, and it is a session-wide fact where the
gate needs a per-delivery one (a keyboard and a gamepad live at once on a
desktop-with-controller session). Classifying at the binding is exact and
engine-free, with no dependency on cross-signal timing.

### A real interaction found while building this: `suspendAxisKeys` must zero the axis it suspends

Repeat exposed (and, on inspection, would have been reachable without it too
— just far less likely to be exercised) a real interaction with the dynamic
Adjust-axis binding seam (`docs/reference/api.md` "Selection, and what moves
it" territory; `presenter.luau`'s `setAdjustBound`/`suspendAxisKeys`): when
focus lands on a contribution declaring `adjustAxis` matching the axis
currently being navigated, `suspendAxisKeys` REMOVES that axis's directional
bindings from `Navigate`/`NavigateH` and rebinds the same keyCodes onto
`Adjust`/`AdjustAxis`. If the physical key was HELD at that moment, the
key-UP that would normally return the action's `Direction1D` to `0` now
arbitrates to the NEW owner instead — `Navigate`'s state was left claiming a
direction it can no longer receive updates for.

Before auto-repeat this was a latent, low-severity bug: `restoreSuspendedNav`
would later rebind the key, but the STALE non-zero value would silently
swallow the very next press of the same direction (`_deliver`'s dedup guard).
With auto-repeat, the SAME stale value would keep the repeat glue firing a
step every interval for a direction the surface no longer owns — a visible,
much more likely-to-trigger defect. Fixed at the source: `suspendAxisKeys` now
zeroes the axis owner's `state` after removing its bindings. This is always
correct — the only way the action's state becomes non-zero again is a FRESH
delivery, which correctly reflects a hold that is live right now — and it
fixes both the pre-existing dedup hazard and the new repeat-outliving-its-
binding hazard with one line. `tests/dpad_repeat.spec.luau`'s Part 3 proves
this by holding a direction through a repeat that lands on an
`adjustAxis`-owning target and asserting the axis's `state` reads `0`
afterward (mutation-proved: removing the fix line reddens the case with
"expected 1 to be 0").

### Analog stick: one repeat path, not two

The `Thumbstick1`-as-d-pad axis tolerance (matrix §D.5) delivers through the
SAME `Navigate`/`NavigateH` actions as the `DPad*` keys, and its binding is
also gamepad-classed, so a fully-deflected stick now ALSO repeats — through
this exact same glue. There is no second, independent repeat path for the
stick to double-fire against: the axis's own deadzone/re-center latch
(`action.bindAxis`) still permits only ONE delivery per crossing regardless
of how long the stick is held past threshold (unchanged), and the repeat
glue's cadence is driven entirely by the presenter's own clock, not by how
often the device re-samples the axis. `tests/dpad_repeat.spec.luau` measures
a held stick's repeat cadence against the d-pad's and confirms they are
identical (not doubled).

## Consequences

- Every presented Facet surface gets gamepad d-pad (and stick) auto-repeat on
  focus navigation with no consumer opt-in and no new option.
- Keyboard arrow-key navigation is byte-identical to before (single step per
  press).
- `Adjust`/`AdjustAxis` (slider/stepper value-adjust via held d-pad) does NOT
  repeat under this change — an explicit scope boundary, not an oversight; a
  future round may extend the same `bindDpadRepeat` helper to those actions
  if the director asks for it, with its own tuning question (adjust-rate is a
  different UX call than focus-advance-rate).
- `action._deliver`'s signature gained an optional second parameter;
  `binding.isGamepad`/`action.lastGamepad` are new internal (not
  publicly-surfaced, per constitution §2's leading-underscore/internal-field
  convention already governing this module) fields on the action pipeline.
  `docs/reference/api.md`'s existing `_deliver`/`_sample` passage is updated
  to match.

## Device-owed

Studio's emulator cannot produce a real gamepad's `InputBegan`/hold timing
(standing rider, binding context) and cannot BE a physical device. Owed on
real hardware:

1. **Console/Ally-class gamepad**: hold each d-pad direction on a real
   multi-item Facet list; confirm the 0.4s/0.1s cadence FEELS right beside
   the platform's own native-selection repeat (there is no scriptable number
   to compare against — a human comparison is the only measurement
   available, per the research above) and that release stops it cleanly.
2. **Same device, analog stick**: hold the stick fully deflected; confirm one
   repeat path (no visible double-speed stepping) and that release/re-center
   behaves the same as the d-pad case.
3. **Desktop keyboard**: confirm a held arrow key still produces exactly one
   step (regression check — the gate must hold on real `InputBegan`, not
   just the headless model).
4. **A live `adjustAxis` control** (e.g. a Slider) reached by holding the
   d-pad through a repeat: confirm focus lands on it cleanly and the axis's
   keys genuinely reach `Adjust` afterward (the `suspendAxisKeys` fix,
   confirmed headlessly but not yet on a real capture/arbitration path).
