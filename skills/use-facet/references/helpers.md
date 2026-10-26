# Extend a task with helpers

Use a standard control when it already owns the behavior. Read only the route
for the needed extension; retrieve these node names with the docs command.
Helpers are not a checklist of features to add to a screen.

| Need | Helper and exact route | Boundary to preserve |
| --- | --- | --- |
| Read room, input or access preferences | `environment` | Layout follows available room; input prompts follow active input. These are separate values. A container source differs from the viewport. Readables end with their owner. |
| Fill remaining stack space | `fill` | Bound the main axis first. Fill is not a generic leaf width or a guarantee that a label fits. Use stack stretch for the cross axis. |
| Mark an existing object | `badged` | Keep the host's hit target. Leave room for a badge painted beyond its bounds. Use a readable count or dot, not essential long text. |
| Enter a passive HUD with a controller | `responder` | Composition already has a responder. Configure that owner instead of adding another. End engagement and restore gameplay on return. |
| Group native focus | `focusSection` | This groups existing targets; it adds neither a target nor commands. Choose entry and return policy. Do not steal focus after the player moved elsewhere. |
| Style focus outside app mounting | `focusRing` | `app.mount` installs this already. Respect custom selection images and dispose the owner. A visual ring does not establish navigation order. |
| Apply commands to keyed native targets | `commandScope` → `Focus-and-command-scopes` | Keys and nodes must be unique. Text entry and more specific modal/control actions win. The scope does not replace directional navigation. |
| Adjust a custom value digitally | `adjustable` | Use one nonselectable readout as the stop, with no selectable descendants. Keep touch/pointer actions outside it. Define allowed directions at limits. Prefer Slider or Stepper for their ordinary tasks. |
| Move data between owned targets | `draggable`, `dropTarget` → `draggable-and-dropTarget` | A gesture is intent. For asynchronous acceptance return `pending`, then call `complete(true)` and update the model only if it succeeds. Cancelled or stale completion must not move data. Provide controller and touch routes. |
| Resolve a custom gesture conflict | `gestureArbiter` | It makes decisions from events you supply; it creates no input listeners. Prefer the standard control's arbitration. Dispose the gesture session on cancellation. |
| Reveal a result in an existing scroller | `scrollTo`, `scrollToVisible` → `scrollTo-and-scrollToVisible` | Call after a meaningful event, not every frame. A false return can mean no movement was needed. Preserve reduced motion and nested scrolling. |
| Attach custom UI to a world target | `worldAnchor` | A projection is not game permission or proximity validation. Define hidden, missing, offscreen and occluded states. The owner releases projection work. Prefer WorldMarker for a standard marker. |
| Explain an accepted change | `sequence`, `countUp` → `Effect-sequences` | Theme tokens own timing. Cancellation or reduced motion must preserve the accepted result. Decorative completion must not grant rewards or save state. |
| Reinforce a rejected action | `shake` → `Effect-sequences` | Shake stable inner faces and retain the rejection reason. The effect restores rotations; do not combine competing rotation owners. |
| Reinforce an accepted action | `feedback` | Haptics supplement a visible or audible result. They cannot be the only error, success or navigation signal. |

For a custom interaction, test entry, activation, cancellation, limits and return
with each supported input. Check that disposal releases commands, subscriptions
and gesture state. A resize or hidden form must not erase a draft or duplicate
a subscription. `ViewThatFits` keeps its candidates mounted; use shared state
and avoid repeated side effects in the alternative forms.
