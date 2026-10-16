# Motion.motionLevel

- The motion level (`motionLevel`, or `GuiService.ReducedMotionEnabled` for
  `"limited"`) changes this motion:
  - `"normal"`: the motion above.
  - `"limited"`: no travel, scale or slide. An Alert, Dialog, Popover, Menu
    (pointer and sheet form), Callout, Button `help` plate and Sheet
    cross-fade in and out over `reducedFade` (0.15 seconds, `easing.fade`);
    a Sheet's panel fades with its scrim. A Toast fades in place over
    `reducedFade` (even with `fade = false`), a TabView page cross-fades
    over `reducedFade`, a NavigationStack push fades the new page in over
    `reducedFade` with no slide (a pop is immediate), and a DisclosureGroup
    or CollapsibleView lands its height at once and fades its content over
    `reducedFade`, and so does a Notice when it arrives and when its close
    button is pressed (`onDismiss` runs after the fade). A NavigationStack pop
    is a known gap: it is immediate. A custom `transition` keeps its own timing. Paint
    transitions keep their timing.
  - `"none"`: every presentation appears and leaves at once, and paint
    transitions are instant.
- A presentation that has not drawn a frame, or whose anchor is no longer
  available, leaves immediately.
- If you present a control again during its exit, the exit reverses.
- PageView keeps its native page swipe.
- Collapsing DisclosureGroup content cannot be interacted with. If the
  selection is in it, the selection moves to the header when the collapse
  starts.
- A Notice whose close button was pressed cannot be interacted with, and it
  clears a selection inside it. If the notice stays mounted after
  `onDismiss`, it opens again.
