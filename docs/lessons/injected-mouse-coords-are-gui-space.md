# `user_mouse_input` coordinates are GUI (AbsolutePosition) space, not where the cursor lands

Observed 2026-07-21 (no-Rojo install verification, Studio 0.730.0.7300790, viewport 1734x1067, `GetGuiInset() = (0,58)`), driving a LuauUI screen whose ScreenGui has `IgnoreGuiInset = true`:

| Injected `moveTo` y | `UserInputService:GetMouseLocation()` | `InputBegan` `InputObject.Position` | Hit? (button `AbsolutePosition` y 44..90) |
|---|---|---|---|
| 9 | 67 (`= 9 + 58`) | **9** | miss — routed above the button |
| 125 | 183 (`= 125 + 58`) | 125 | miss — routed below the button |
| 67 | 125 | **67** | **hit** — `Activated` + `MouseButton1Down/Up` fired, `gameProcessed = true` |

**Rule: pass the target GuiObject's `AbsolutePosition` (+ half its `AbsoluteSize`) to `user_mouse_input` verbatim.** The engine adds the GUI inset when it places the *physical* cursor, so the visible pointer lands 58px lower than the number you injected — that is correct and expected, not a miss. Verify the target with `PlayerGui:GetGuiObjectsAtPosition(x, y)` using the *same* AbsolutePosition-space numbers before clicking.

The trap: `GetMouseLocation()` and the drawn cursor agree with each other and *disagree* with the routed input by exactly the inset, so a click that looks perfectly aimed on screen (and in a screenshot) routes 58px away. Chasing the cursor instead of the input object costs several rounds.

Two more notes from the same session:

- `user_mouse_input`'s `instance_path` cannot address LuauUI nodes: their names are paths (`/Counter/Bump`) and the tool's path parser splits on `.`/`/`. Use x/y.
- To tell a *pointer* activation from an *action-system* activation, count both: connect `GuiButton.Activated` and compare against the app-level effect. Enter-key activation bumped the app state while the button's own `Activated` count stayed flat — that is the action system dispatching, not the widget.

## Addendum 2026-07-26 — a TOUCH-booted device-emulator session shifts the routed position

The rule above holds exactly on a desktop-booted session: injecting `(315, 970)` produced `InputBegan` `MouseButton1` at `(315, 970)` and hit the button whose `AbsolutePosition` was `(306, 947, 202x46)`.

A Play session **booted on a phone preset** (`samsung_galaxy_a06`, `TouchEnabled = true`, `PreferredInput = Touch`) behaves differently, measured twice at two different targets (Studio 0.731.0.7310942, emulated viewport 359x718):

| Injected y | `GetMouseLocation()` | routed `InputObject.Position` y | class |
|---|---|---|---|
| 600 | 611 | **553** | `UserInputType.Touch` |
| 668 | 679 | **621** | `UserInputType.Touch` — hit the button at Gui y 576..644 |

So on a touch-booted emulator session the injected click arrives as **`Touch`, not `MouseButton1`**, and the routed position is `injected − 47` in y (`GetMouseLocation() − 58`), x unchanged. The 47 is preset-dependent — the emulator draws a device frame and fits the emulated screen into the game view — so **discover it, do not assume it**: inject once, read `InputObject.Position` off `InputBegan`, then aim `target + (injected − routed)`. A first click that lands 23px above a 68px-tall button produces *no* event at all and looks exactly like a broken fix.

## Addendum 2026-08-15 — `GetMouseLocation()` FREEZES under an active device simulator, and the readback it is used for is the calibration itself

Driving the showcase (Studio 0.735, place `LuauUI-Showcase.rbxl`) the rule above
held exactly at the **default** viewport (907x1067): `moveTo (38, 89)` put
`GetMouseLocation()` at `(38, 147)` — `injected + inset` — and `moveTo (271, 134)`
aimed at a `Grip`'s own `AbsolutePosition` centre resized the column by exactly
the 100px dragged. Injected x/y is AbsolutePosition space; nothing new.

With `StudioDeviceSimulatorService` **active** (`samsung_galaxy_a06`, portrait,
359x718) the same readback stopped moving:

| Injected `moveTo` | `GetMouseLocation()` |
|---|---|
| `(280, 281)` | `(150, 293)` |
| `(100, 100)` | `(150, 293)` — *identical, two calls later* |

Two different aim points, one answer. `GetMouseLocation()` was not merely
offset (the case the addendum above documents) — it had **stopped tracking
altogether**, and `(150, 293)` was stale from an earlier gesture.

**Why that is worse than an offset.** The published recipe for the offset is
"inject once, read the position back, add the delta". If the readback is a
frozen constant, that calibration returns a *constant* delta, every subsequent
click is aimed at the same wrong place, and each one produces a plausible
result: in this session a swipe aimed at mail row `m2` opened row `m1`, which
reads exactly like an off-by-one-row bug in the row-actions coordinator. It is
not. The framework was correct; the instrument was frozen.

**The readback that stayed truthful is `PlayerGui:GetGuiObjectsAtPosition(x, y)`,
which takes the same AbsolutePosition-space numbers you inject.** It is pure
geometry against the live tree, it has no cursor in it, and it answered
correctly under simulation when `GetMouseLocation()` did not. Use it — not the
cursor — to prove where an aim point lands:

```lua
-- BEFORE clicking: does this coordinate actually sit on the thing I mean?
for _, h in pg:GetGuiObjectsAtPosition(x, y) do print(h.Name, h.ClassName) end
```

So the rule for a device-simulator session becomes:

1. **Never calibrate from `GetMouseLocation()` while a device is simulated.**
   Calibrate from `InputBegan`'s `InputObject.Position` (already the advice
   above) or not at all.
2. **Aim-check every coordinate with `GetGuiObjectsAtPosition` first**, and
   name the instance you expect. One extra read turns "the feature is broken"
   into "my pointer was 46px high" before the bug report is written.
3. **When the mapping cannot be established, drop the simulator.** Verifying a
   *gesture* at the default viewport with a proven identity mapping is better
   evidence than verifying it on the right form factor through a lying one. The
   swipe above was re-proved at 907x1067 — pointer landed exactly where
   requested, `GetGuiObjectsAtPosition` confirmed row `m3`, and `m3` was the row
   that opened while the previously-open row auto-closed.

## Addendum 2026-08-16 — the same offset READ BACK looks like a layout defect

The rule above is about the numbers you *inject*. It is also about the numbers you
*read*, and read the wrong way round it manufactures a defect that is not there.

Inspecting the HUD showcase live (Studio 0.734, 749x380, `GetGuiInset() = (0,58)`)
produced this, and it was written up as a fourth failure class — a node painted
entirely above the top of the viewport, worse-behaved than elision because nothing
knew it had happened:

```
Round 3 · Capture    @(416,-37) 81x15      vis=true   -- y + h = -22
```

It is not painted above the viewport. A LuauUI ScreenGui renders
`IgnoreGuiInset = true`, and **`AbsolutePosition` on such a tree is reported in the
inset-subtracted space**: the top of the window reads back as `-GetGuiInset().Y`.
The headless twin, driven at the same size with the same chrome facts, puts the
same node at window **y 21, h 15** — inside the platform's 0..58 band, which is
exactly where ADR-0027 requires it. `21 - 58 = -37`.

**Two checks that settle it without a second Studio session**, both from the same
capture:

1. **Compare an axis the inset does not touch.** Live `x=416 w=81` centres at
   456.5; the headless twin's `x=393 w=127` centres at 456.5; the free band
   (`x 164..749`) centres at **456.5**. Identical on x, off by exactly the inset on
   y, is an offset — not a layout.
2. **Look for the origin.** The same capture reported three HIDDEN nodes at
   `y = -58` (they are parked at the composition's origin, i.e. window y 0). A
   capture in which window-space 0 reads back as `-58` has a `-58` offset in it.

**Rule: before diagnosing a negative `AbsolutePosition.Y`, add `GetGuiInset().Y`.**
A LuauUI node whose reported y is `-inset` is at the top of the window; one whose
reported y is `0` is `inset` px down. The pinned regression is
`tests/elision_recovery.spec.luau` ("the objective chip is inside the platform's
band at 749x380, not above the screen"), which asserts the invariant in window
space at the very viewport this report was taken at.

Related: [`injected-input-offset-is-per-configuration.md`](injected-input-offset-is-per-configuration.md),
[`device-emulator-truths.md`](device-emulator-truths.md).
