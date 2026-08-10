# Task 6 touch spike — findings and decision

**Date:** 2026-08-10. **Studio:** Place1 (empty baseplate), Studio MCP, device
emulator set to `iphone_6_Plus` (736x414, `ActualResolution` scaling) via
`StudioDeviceSimulatorService:SetDeviceAsync`/`SetScalingModeAsync` in the Edit
datamodel, then Play. Sync server: `lune run tools/lune/studio_sync` restarted
fresh immediately before the session (killed a stale listener first — the
stale-file-list trap, `docs/lessons/sync-server-file-list-is-startup-frozen.md`)
and confirmed `manifest 248 nodes` in the fresh process's own log line.

## What was built

A raw-Roblox-instance fixture (not LuauUI-mounted — deliberately, see "Why raw
instances" below), pushed as a `LocalScript` (`StarterGui.TouchSpike`, deleted
after the session) so its event connections survive independently of any one
`execute_luau` call (per the standing `_G`-does-not-cross-calls trap): a
`ScrollingFrame` (`ScrollingDirection = Y`, `AutomaticCanvasSize = None`,
explicit `CanvasSize`) holding six `180px`-tall `Frame` rows. Every row sets
`Active = true` (mirrors `UI.Grip`'s own "non-button Active pointer zone: sinks
presses without being a GuiButton", `src/client/screen_target.luau`) and wires
**both** candidates simultaneously so one drag tells you about both:

- **Candidate (a)** — `InputBegan` (local instance) → on `Touch`/`MouseButton1`,
  connect `UserInputService.InputChanged`/`InputEnded` for the gesture's
  duration. This is the **exact** mechanism `screen_target.luau`'s real
  `adapter.setPointerHandlers` already uses (verified by reading the adapter
  source, not assumed — see "Code-trace evidence" below), copied faithfully
  including the global-service-level `InputChanged`/`InputEnded` subscription
  (not `instance.InputChanged`). Two row variants: `observe` (logs every move,
  never goes inert — proves raw delivery only) and `accept` (mirrors
  `row_actions.luau`'s own `onPointerMove` exactly: axis-lock at 8px, then
  **inert** on a `"vertical"` verdict — the open question this spike exists to
  answer: does an *accepted-then-inert* capture interfere with the
  `ScrollingFrame`'s own native scroll?).
- **Candidate (b)** — `instance.TouchTap`/`TouchPan` connected directly on the
  same row (the engine GESTURE-recognition path `src/input/touch_gestures.luau`
  normalizes).
- `Body:GetPropertyChangedSignal("CanvasPosition")` logs every native-scroll
  tick, so a drag's effect on scroll is directly observable.

Every event logs through `print("RASPIKE|...")` **and** a `BindableFunction`
(`workspace.SpikeLog`) returning the structured log as JSON, so a result
doesn't depend on the console buffer alone.

### Why raw instances, not a mounted `newRowActions`

The question under test — "does the engine's own `InputBegan`/`TouchPan`
delivery and `ScrollingFrame` scroll-arbitration behave as expected inside a
real native Y-scroll host" — is a platform fact about `GuiObject`/
`ScrollingFrame`, not about LuauUI's blueprint/solver/renderer plumbing. The
real adapter's `setPointerHandlers` (traced below) connects to exactly the same
signals a raw `Frame` with `Active = true` would; building the full gallery
scenario pipeline to test an engine fact would add mounting/sync surface
without changing what's actually being measured, and would have cost most of
the timebox on scaffolding rather than the answer.

## What actually happened: the emulator step succeeded, the input-driving step did not

**Device emulator selection is now MCP-drivable** (an improvement over the
prior `NS-M4` finding, `artifacts/native-substrate/feasibility/m4-touch-events.json`,
2026-07-23, which recorded "Studio device emulator cannot be enabled by the
MCP"). `StudioDeviceSimulatorService:SetDeviceAsync("iphone_6_Plus")` +
`SetScalingModeAsync(ActualResolution)` both returned `ok = true` from the Edit
datamodel, and once Play started the Client datamodel confirmed the emulated
device took effect: `UserInputService.TouchEnabled = true`,
`GetLastInputType() = Enum.UserInputType.Touch`, and a `TouchGui` instance was
present under `PlayerGui` (the engine's own on-screen touch-control chrome,
which only mounts when the client believes it is a touch device) — none of
which was true in the July session's desktop-only Play Solo.

**But every screen-driven MCP tool timed out, consistently, on both
candidates and on the diagnostic tools alike:**

| Tool call | Result |
|---|---|
| `screen_capture` (first, before any input attempt) | `MCP error -32603: Request timeout` |
| `user_mouse_input` (4-step drag: moveTo/down/3×moveTo/up) | timeout |
| `user_mouse_input` (4-step drag, shorter) | timeout |
| `user_mouse_input` (single `moveTo`) | timeout |
| `screen_capture` (diagnostic retry) | timeout |
| `user_mouse_input` (single `moveTo`, retry) | timeout |

Six consecutive failures, **only** on tools that need to interact with a
rendered/visible Studio window — every backend-only call in between
(`execute_luau`, `get_console_output`, `get_studio_state`) succeeded
immediately and repeatedly, both before, between, and after these attempts.
This rules out "Studio disconnected" (the brief's stated bail condition) — the
MCP bridge and the running Play session were both healthy the whole time — and
instead points at this specific session having no attached display for the
Studio window to actually render into, so nothing that requires driving a real
on-screen cursor or reading real pixels can complete. Per the brief ("if Studio
tools error twice in a row... STOP... do not thrash"), stopped after six.

**`VirtualInputManager` re-confirmed locked, independently, today** — tried as
the brief's suggested fallback, from `execute_luau`'s own Client-datamodel
context (a higher-privilege caller than a real game `LocalScript`, on the
theory that the MCP bridge might run with more capability than the July
investigation's assumption):

```
VIM:SendTouchEvent(...)      -- "lacking capability RobloxScript"
VIM:SendMouseMoveEvent(...)  -- "lacking capability RobloxScript"
VIM:SendMouseButtonEvent(...) -- "lacking capability RobloxScript"
```

All three throw the identical capability error the 2026-07-23 `NS-M4` spike
recorded (`artifacts/native-substrate/feasibility/m4-touch-events.json`:
`"VirtualInputManager:SendTouchEvent is RobloxScript-locked from
execute_luau"`) — this is not a session fluke, it is a structural Studio/MCP
boundary, reconfirmed independently five weeks later against current tooling.
`SendTouchTapEvent`/`SendTouchPinchEvent`/`SendTouchRotateEvent`/
`SendTouchSwipeEvent` are not even members of the object (only
`SendTouchEvent`, `SendMouseButtonEvent`, `SendMouseMoveEvent`,
`SendMouseWheelEvent`, `SendKeyEvent` exist) — narrower than the brief assumed,
recorded so a future session doesn't re-probe the missing ones.

The console and the live `CanvasPosition` both confirm nothing was ever
delivered: zero `RASPIKE|BEGAN`/`CHANGED`/`TOUCHPAN`/`CANVASPOS` lines beyond
the fixture's own `READY` line, and `body.CanvasPosition` unchanged at
`(0.0, 0.0)` after every attempt.

**This session cannot produce live touch-firing evidence for either
candidate.** The brief anticipated a narrower version of this exact trap
("the emulator cannot produce `preferredInput = Touch`... note this in the
artifact") — this session's finding is stronger: the emulator *did* produce
`preferredInput = Touch` and `TouchEnabled = true` (an improvement over the
prior spike), but *no MCP tool in this session could drive any input event
into the running client at all*, screen- or script-level alike. Both are
recorded as distinct facts because they are — a future session with a real
attached display, or a physical/retail device, is what closes `NS-P2` for
`RowActions` too.

## Deciding without live firing: the evidence that remains

Three independent, non-speculative sources, none of them a guess:

**1. Code-trace: touch already flows through the exact seam mouse uses, today.**
`src/client/screen_target.luau`'s real `adapter.setPointerHandlers` (not the
headless fake) connects `instance.InputBegan`, then
`UserInputService.InputChanged`/`InputEnded`, checking
`UserInputType.Touch` **alongside** `MouseButton1`/`MouseMovement` at every
step (lines ~2875-2932) — `pointerTypeOf` reports `"touch"` vs `"mouse"` from
the same `InputObject`. Nothing about the adapter's touch delivery is
speculative or partially built: `_pointerHandlers.onPointerDown/Move/Up/Cancel`
already receive real touch positions whenever a presenter mounts a `Grip`/
`Button` with those props. `row_actions.luau`'s own `onPointerDown` is the
**only** thing declining it (`pos.pointerType ~= "mouse"` → `return false`,
Task 5). Candidate (a) requires zero adapter work — only removing that one
guard and reusing Task 5's already-built axis-lock/inert dance.

**2. Precedent: this framework already ships (and device-verified) the same
shape — an accepted touch capture on a small hit-zone, coexisting with the
same `ScrollingFrame`'s native vertical scroll, in the same control family.**
`table.luau`'s edit-mode ≡ handle is a dedicated `Active` pointer zone that
**accepts** a touch capture (does not decline) to drive column reorder, sitting
inside the identical native Y-scrolling `Body` ordinary rows scroll in — and
the registry's own citations for `Table` are marked device-true, not just
headless: `inputProofs.touch = { "a TOUCH drag on the grip previews and
commits the new column width", "a TOUCH grip drag clamps to the column
minWidth" }` and `affordanceProofs.touch = { "a touch drag on the row body
defers to the native scroll and never reorders", "edit mode grows a trailing
handle per row; a TOUCH drag on the handle reorders" }`
(`tests/conformance/controls_registry.luau:107-145`). This is not the identical
shape (Table's handle is a narrow edge grip, RowActions' `Hit` covers the whole
row; Table's own row *body* still declines touch, letting native scroll own it
unconditionally rather than axis-locking) — but it is real, shipped, verified
evidence that an `Active` GuiObject accepting a touch capture and driving a
drag from it does not structurally break a sibling native `ScrollingFrame`'s
own vertical touch-scroll in this exact codebase's adapter.

**3. `TouchPan` (candidate b) is independently confirmed unusable in Studio,
twice, five weeks apart** — `NS-M4`/`NS-A6` (2026-07-23) and this session
(2026-08-10) both hit the identical `RobloxScript`-capability wall trying to
fire it synthetically. A control built against it would ship with **zero**
Studio-verifiable coverage of its own primary gesture path — only
`onGesture`'s pure normalization (`tests/touch_gestures.spec.luau`) would ever
run, never a real `instance.TouchPan:Connect` firing. Candidate (a), by
contrast, is verified the same way Task 5's mouse gesture already is: through
the real `fake_target.luau` adapter headlessly (`pointerType = "touch"`
variants of the exact same drag cases), which is a faithful proxy for the real
adapter because both real and fake deliver through the identical
`onPointerDown/Move/Up/Cancel` shape — confirmed by the SAME code trace in
finding 1.

**4. Architectural fit: `touch_gestures.newArbiter` exists to arbitrate
*multiple simultaneous* gesture streams (pinch/rotate outranking pan) — a
problem `RowActions` does not have.** It needs exactly one continuous
single-finger drag with an axis decision, which `row_actions_state`'s
`axisVerdict`/`clampDrag`/`settle` already model completely and exclusively.
Routing touch through the arbiter would mean **duplicating** the axis-lock/
threshold logic in two places (the arbiter's rank table, which has no axis
concept at all, cannot express "tie goes vertical, scrolling must never lose
an ambiguous gesture") or reaching back into `row_actions_state` from a second
call site — against the brief's explicit constraint that the state module
owns axis lock and settle, unchanged.

## DECISION

**Candidate (a) — extend `_pointerHandlers` to accept `pointerType == "touch"`
with the identical tentative-accept + axis-lock + inert-on-vertical dance Task
5 already built for mouse.** No new decision logic: the same
`row_actions_state.new(...).axisVerdict`/`clampDrag`/`settle` calls, the same
capture-semantics constraint Task 5's own investigation already proved
(`onPointerDown` cannot decide the axis at down-time and must accept
tentatively; a `"vertical"` verdict is honored by going inert, not by
un-capturing — there is no third option, ADR-0008). The only change to
`onPointerDown` is narrowing the decline guard from `pointerType ~= "mouse"`
to `pointerType ~= "mouse" and pointerType ~= "touch"` (pen/stylus and any
other exotic pointer type still decline, matching the existing boundary's
intent — "mouse or touch, nothing else yet").

Candidate (b) is not adopted: it cannot be verified in this environment at
all (finding 3), it does not reuse work Task 5 already built and tested
(finding 1), it would duplicate axis-lock decision logic the brief requires
stay singular (finding 4), and this framework already has real, device-true
precedent that the raw-capture shape candidate (a) uses is safe next to a
native `ScrollingFrame` (finding 2).

## Residual risk, stated plainly

The one thing this spike could not produce is a live trace proving an
*accepted-then-inert* touch capture never blocks the `ScrollingFrame`'s own
native vertical scroll on the very same row it started on (as opposed to
Table's handle, which is a separate zone from the scrolling rows). This stays
open, not asserted closed:

- `PENDING_PHYSICAL` / `PENDING_STUDIO_INPUT` — closed by a future session with
  either a real attached display (so `user_mouse_input`/`screen_capture` can
  actually drive and capture) or a physical/retail touch device, following the
  same procedure this spike attempted. Recorded here so a later task does not
  have to rediscover that this specific gap (not the whole touch story) is
  what's outstanding.
- Mitigated, not closed, by: the code-trace (finding 1) showing `InputBegan`/
  `InputChanged`/`InputEnded` are raw, non-exclusive, non-gesture-recognized
  signals — Roblox's documented model has every `GuiObject` under a touch
  point receive them independently of each other and of the engine's own
  gesture recognizers (`TouchPan`, which is what `ScrollingFrame`'s native
  scroll is actually built on) — so accepting them is not, by the platform's
  own event model, a competing claim on the same recognizer `ScrollingFrame`
  uses. This is platform-semantics reasoning, not a live trace, and is named
  as such.

### Retry, same day, second session — the two named facts are STILL not obtainable live

A second session was explicitly reported by the coordinator as MCP-healthy
(`list_roblox_studios` showed `Place1` active; `get_studio_state` returned
`Edit` cleanly) and asked for a retry scoped to exactly the two open facts:
(a) does an accepted-then-inert touch capture on a row ever block native
vertical scroll of the `ScrollingFrame`; (b) does the `ScrollingFrame` steal
an in-progress horizontal pan once it starts scrolling vertically from a
different gesture.

Setup was re-verified clean and healthy at every backend step:

1. `list_roblox_studios`/`get_studio_state` — healthy, `Place1` active, `Edit`.
2. Spike fixture re-injected (identical script, same `StarterGui.TouchSpike`
   `LocalScript`) and device emulator re-set to `iphone_6_Plus` +
   `ActualResolution` — both `execute_luau` calls returned `ok = true`
   immediately, same as the first session.
3. `start_stop_play(is_start = true)` — succeeded. **Verified the state
   actually flipped**, per the retry instructions, via a follow-up
   `get_studio_state` call (not assumed from the start call's own return):
   `Current Studio Mode: Play`, `Available DataModels: Client, Server`,
   `Focused DataModel in the viewport: Client`. Play-mode entry itself is NOT
   part of this session's failure — it is healthy.
4. Fixture confirmed live and correctly laid out via `execute_luau` (Client):
   `Body abs=(20,20) size=(340,480)`, four rows at their expected offsets,
   `TouchEnabled = true`, `LastInputType = Enum.UserInputType.Touch` — an
   exact repeat of the first session's healthy pre-drive state.
5. `user_mouse_input` (a 4-step vertical drag on RowA: `moveTo(150,120)` →
   `mouseButtonDown` → `moveTo(150,30)` → `mouseButtonUp`) — **timeout**.
   Retried immediately, identical payload — **timeout** again. Two
   consecutive failures on the input-driving tool specifically, exactly the
   coordinator's named stop condition.
6. Health re-checked immediately after (not assumed): `get_console_output`
   and `get_studio_state` both returned instantly and correctly (`Play`,
   `Client` focused) — the bridge and the running session were both healthy
   the whole time; only `user_mouse_input` itself failed to complete, twice
   in a row, with no partial effect (console held only the fixture's own
   `READY` line both before and after; no `BEGAN`/`CHANGED`/`CANVASPOS` lines
   ever appeared).

Per the coordinator's explicit instruction, stopped there — cleaned up
(`start_stop_play(is_start = false)`, deleted `StarterGui.TouchSpike`) rather
than continuing to retry a call that had now failed identically across two
separate sessions on two different dates in the same way (screen/input-driving
tools time out; every backend-only call stays healthy throughout).

**Facts (a) and (b) remain unobtained live, in this environment, across two
independent attempts.** This is now a corroborated, repeatable finding — not
a single session's bad luck — and reads as a structural limitation of
`user_mouse_input`/`screen_capture` in whatever hosts this Studio instance
(most consistent with no attached display for the Studio window to render
into, unchanged from the first session's diagnosis), not a fixable retry
target. The DECISION above does not change: it was never conditioned on
obtaining this evidence, precisely because the first session already
established it might not be obtainable here. Closing facts (a)/(b) now
requires either a real attached display or a physical/retail touch device —
recorded as the standing follow-up, same as `NS-P2`.

## Implementation note

Touch differences from mouse, preserved in `src/controls/row_actions.luau`:
the tentative-accept-then-inert-on-vertical dance is now shared, unchanged,
between `pointerType == "mouse"` and `pointerType == "touch"` — no branch
distinguishes them anywhere in `onPointerDown`/`onPointerMove`/`onPointerUp`/
`onPointerCancel` past the initial decline guard, matching the spec's own
framing ("the state module owns axis lock and settle" — device-agnostic by
construction, not by special-casing). Headless coverage: `pointerType =
"touch"` variants of Task 5's own drag/open/commit/flick/cancel cases, driven
through the real `fake_target.luau` adapter exactly like mouse (see finding 1
for why that adapter is a faithful proxy). The registry's `hotSwitch` claim is
revisited honestly now that a second real input class can touch `drag`-in-
flight state — see `tests/conformance/controls_registry.luau`'s `RowActions`
row and its own updated comment.
