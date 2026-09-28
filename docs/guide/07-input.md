# Input and focus

## Mechanisms

These native mechanisms do the input work:

- GuiButton activation,
- TextBox editing,
- native InputContext and InputAction bindings,
- GuiService selection,
- UIDragDetector.

Compose owns their Instances and subscriptions. Facet supplies the control
eligibility and the interaction policy. Input contexts are siblings under a
native host. Do not nest them.

## Selection rules

The engine moves the selection. Facet adds these rules, which the focus graph
on main also had:

- The first D-pad press selects the first control when nothing is selected.
- Tab and Shift+Tab walk the controls in layout order and wrap.
- A removed control gives the selection to its nearest neighbour.
- A scroll container is not a selection stop.
- A value control keeps Left and Right for its value.

See [Selection](../reference/api.md#selection) for the full rules.

## Focus navigation: engine facts

Measured live in Studio with the Controller Emulator (studio-emulated, not a
physical pad), with the `focus_probe` live suite and the Showcase.
The emulator's stick is digital: every push is full deflection. Evidence:
`artifacts/studio-live/focus-probe-t2.json` and the focus atlases in
`tests/fixtures/focus_atlas`.

| Id | Question | Measured (D-pad / stick / arrows) | Facet relies on the engine, or custom code |
|---|---|---|---|
| `F1` | Overlap or distance? | A candidate that overlaps the move's cross axis wins over a nearer one that does not (D-pad and stick). Among overlapping candidates the nearest leading edge wins, even with a large centre offset. | Engine. The query's in-beam rule matches. |
| `F2` | Up from Boost on a form column (`M2`) | Plain frames: Rear (D-pad and stick). The Showcase went to a toolbar button or to Boost's own track before `E2` and `F4` were fixed; it now reaches Rear. The stick does not move from Rear Up or Right when the only target is far off its axis (the D-pad takes it). | Engine; no column rule. |
| `F3` | Does the stick honour links? | Yes. A self-link holds the stick, a link to C moves it to C. | Engine (value controls pin their axis with a self-link). |
| `F4` | Is a drag detector's parent a stop? | Yes. An enabled `UIDragDetector` makes its `Selectable = false` parent a D-pad and stick target. `Enabled = false` removes it. | Custom: Slider detectors are off while the gamepad is the preferred input. |
| `F5` | What do SelectionGroups do? | Members win over a nearer outside candidate. `Stop` holds the selection; `NextSelection*` on the group frame is ignored under `Stop`; a link on the member crosses `Stop`. Nested: an inner `Stop` holds, and an outer `Stop` holds through an inner `Escape`. | Engine. The query models it. |
| `F6` | Scroll children | From inside a ScrollingFrame, its children are targets even when clipped or off the screen, and the frame scrolls to them. From outside, a child clipped out of the window is skipped; a selectable ScrollingFrame is itself a target (Facet passes the selection into it). Controls fully off the screen and not in a scroll container are never targets. | Engine; the query models the clip rule and Facet's container entry. |
| `F7` | Rotation, CanvasGroup | A rotated frame and a CanvasGroup child are ordinary targets. | Engine. |
| `F8` | Stick while a value control is selected | See `E1`. A diagonal push (the emulator gives (1, 1)) on a horizontal Slider moves the selection and does not adjust. | Custom stick reading (`E1`). |
| `F9` | Arrow keys | Pending: the Controller Emulator swallows every keyboard key while it is on. | |
| `F10` | L1 and R1 | L1 does not move the selection between groups. An InputAction bound to L1 still fires while something is selected (the value controls' Decrease). | Engine. |
| `F11` | Where is the ring drawn? | On `FacetFocusPart` under an ancestor `UIScale` (0.6): on the part. On a rotated stop the ring turns with the stop but sits off the part (known limit). | Custom part placement. |
| `F12` | Ranking out of the beam | With no overlapping candidate, the engine takes the one best aligned with the move (smallest cross offset over distance), even when it is much farther: from a control, Right chose a target 18 degrees off the axis over a nearer one 40 degrees off. The query ranks these by gap plus twice the centre offset (decision `D5`), so such moves are listed in `divergences.json`. | Engine; the query differs (owner decision pending). |
| `F13` | Page state during the walk | A move can reveal a control that was hidden when the atlas was taken. | Walk tool: listed in `divergences.json` as `F13`. |
| `E1` | Input actions while something is selected | While `GuiService.SelectedObject` is set, no InputContext (any priority, sink or parent) receives the D-pad or the left stick. With nothing selected, a Direction2D action on `Thumbstick1` fires. | Custom: value controls read the stick from `UserInputService` and the D-pad from `InputBegan`. |
| `E2` | Wired targets first | The D-pad ranks every candidate with a `SelectionGained`, `SelectionLost`, `Activated` or `MouseButton1Click` connection ahead of every candidate without one. `InputBegan`, `Changed` and property-changed connections do not count. The stick ignores this. | Custom: each value control's stop listens for `SelectionGained`. A game's own selectable Frame needs a listener too, or buttons win over it. |
| `N-5` | The selected object stops being a stop | Turning it `Selectable = false`, `Visible = false` or `Interactable = false` moves the selection to another control at once. | Engine (a busy control keeps its stop). |
| `M1` | Stepper, stick Left | Before: the stick held the selection and did not change the value. After: D-pad, stick and arrows change the value, Down leaves. | Custom (`E1`). |
| `M2` | Up from Boost | Before: a toolbar button, or Boost's own track. After: Rear (D-pad and stick). | Custom (`E2`, `F4`). |

## Modal controls

A modal control:

- traps all native selection directions,
- selects an enabled initial item,
- owns the Back input,
- restores the previous selection if that object still exists.

The `GuiButton.Modal` property affects mouse locking. It is not a focus trap.

## Text input

TextInput keeps user edits separate from model synchronization. The engine owns
IME, the caret and the text selection. The control owns validation, numeric
bounds, and the change, commit and cancel behavior. An external model write
does not send an edit callback.

## Virtual collections

Virtual controls keep logical focus with Compose keys. They scroll through the
collection controls. They restore `GuiService.SelectedObject` when the
requested row exists. Keyboard and gamepad traversal must not depend on every
item being mounted.

## World surfaces

World-fixed UI is a flat two-dimensional SurfaceGui. Facet does not add VR,
gaze input, hand input or declarative three-dimensional layout. See
[native targets and boundaries](../reference/api.md#native-targets-and-boundaries).
