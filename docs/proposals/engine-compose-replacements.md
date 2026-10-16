# Engine and Compose boundaries

Use native Roblox mechanisms first, then the pinned Compose API. Facet keeps
control-specific policy. The dependency pin is in
`src/vendor/compose/UPSTREAM.lock`.

## Current mechanisms

| Topic | Mechanism | Facet policy |
| --- | --- | --- |
| Effect sequences | Compose `runtime.sequence` and `runtime.tween` | Resolve theme timing tokens and control callbacks in `src/ui/effect_sequence.luau`. |
| Environment observation | Compose `runtime.observe` and native property signals | Preview values, input withholding, and selection policy in `src/ui/context_observe.luau`. |
| Reveal readiness | Compose `runtime.settled` | Which native text and geometry facts must be ready before a control appears. |
| Timers and deferred work | Compose `runtime.clock` and `runtime.scheduler` | Deadline formatting, text reveal and control cancellation. |
| Focus ring lifetime | Native input events and Compose `runtime.connect` | Focus visibility in `src/ui/environment.luau`. |
| Layout | UIListLayout, UIGridLayout, UIFlexItem, and UIPadding | Convert control specs and theme metrics. |
| Virtual collections | Compose OrderedCollection | Row presentation, selection, and sort policy. |
| Scrolling | ScrollingFrame and CanvasPosition | Nested gesture handoff and control-specific anchoring. |
| Input | InputContext, InputAction, and UIDragDetector | Action eligibility, range validation, and commit policy. |
| Overlays | Native screen layers and Compose portals | Safe-area placement, dismissal, and selection restoration. |

## Evaluate a replacement

Check the native API and the pinned Compose API before removing Facet policy.
A similar method name does not prove equivalent behavior. Compare callback
order, cancellation, resource cleanup, reduced motion, and interrupted motion.

For geometry observation, keep the frame and polling options on Compose
`runtime.observe`. Compose owns the shared read-before-publish pass and
cancellation. Native property signals report changes; they do not by themselves
coordinate measurements across controls. Do not restore a Facet observation queue.

For focus traversal, preserve modal scope, hidden-ancestor checks, document
order, text focus, and entry selection. Native selection and directional links
do not collect Facet's candidate tree.

For Table sorting, check the first row and the selected row at wide and compact
sizes. Include horizontal scroll, ancestor UIScale, hidden or removed rows,
wrapped rows, and rows taller than the viewport.

For nested scrolling, test actual touch handoff between ancestors. Native
ElasticBehavior alone does not prove the required gesture policy.

Use a regression spec for each behavior difference. Run Studio checks for
geometry, input, and motion. A native engine double proves policy and ownership;
it does not prove engine behavior. Add a missing general mechanism upstream in
Compose, then re-pin. Do not edit the generated snapshot.
