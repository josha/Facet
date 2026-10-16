### Alert

<!-- aliases: Alert | alert -->

Supply a writable boolean `isPresented`, or a writable `item` cell where `nil`
means hidden. Also supply `title`, `message` and `actions`. The alert captures
the item payload for the active presentation and gives it to the content and
callback factories. `title` and `message` accept a string, a readable string,
a string formula, or a callback that returns a string for the item payload.

Actions have `id`, `label` and `role`, and an optional `enabled`, `shortcut` and
`onActivate(payload)`. Dismissal occurs before the action callback.

The control owns the initial selection, selection containment, Back and cancel,
and restoration to the previous selection if that object still exists.

Motion options:

- `transition = { source = nativeNode, seconds = 0.2, ease = Compose.easing.outQuad }`
  enables native source motion. `source` can also be a readable.
- `surface = "fullScreen"` fills the native presentation area. The content
  and the actions stay in a centered column. The column is not wider than
  `maxWidth` (default 960 pixels).
- With `surface = "fullScreen"` and a source transition, both bounds
  interpolate from the source rectangle. The alert content keeps its final
  size and the growing panel clips it. A non-interactive native snapshot at
  the source size covers the start of the handoff and fades out in the first
  35 percent of the motion. Dismissal fades it in during the last 35 percent. Dismissal reverses to the source if
  it still exists. Compose owns the snapshot and the departing presentation.
  The source stays mounted.
- Native reduced motion makes the handoff immediate.
- Without `transition`, the complete alert fades in at its final size. See
  [Motion](Motion.md).
- `transition = false` makes the presentation immediate.

The alert clears a writable `error` on dismissal. Use an alert for a brief
decision. `icon`, `severity`, suppression and custom content refine the
presentation. The `suppression` checkbox sits below the actions.
