### Vote

Vote is up, down or none over your value. It requires `value` (`up`, `down`
or `none`, or a readable of one) and `onChange(next)`, unless `readOnly` is
true. `summary` is your own text, such as "99% liked". The optional
`controlSize`, `enabled` and `controls` apply. The control sets
`controls.diagnostics()`.

- The caller owns `value`. A press calls `onChange(next)` once. The strip
  changes only when your value changes. Thus a refused vote never paints, and
  a change from up to down is one change.
- A press on the chosen side proposes `none`.
- The two sides are icon Buttons (`vote.up`, `vote.down`) with the names
  "Upvote" and "Downvote", in the `facet-segmented` strip that Picker uses.
  The chosen side has `facet-segment-current`. Each side is at least the
  target size (`targetSizes.minimum`).
- The summary is one line. Its whole text is in the `FacetLabel` attribute.
  Vote counts nothing.
- `readOnly = true` shows the same icons with your choice marked, with no
  Button and no selection stop. It is not disabled paint. A later
  `readOnly = false` without `onChange` keeps the vote read-only, with a
  warning and a diagnostic line. Each read-only mark has the size of an
  interactive option at the same `controlSize`: the rung height, and not less
  than `targetSizes.minimum`.
- `enabled = false` gives the ordinary disabled Buttons. A late value that is
  not legal keeps the last legal value.

Pointer and touch press a side. Native gamepad selection moves between the
sides. The Activate action (Return or Space) and ButtonA propose the selected
side. The root has the attributes `FacetValue` and `FacetReadOnly`. For a
score out of five, use Rating. For a number that the player adjusts, use
Stepper.
