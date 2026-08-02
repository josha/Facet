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
