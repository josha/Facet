### StepIndicator

<!-- aliases: StepIndicator | stepindicator -->

StepIndicator shows where a workflow is. It shows a list of step states. It
is not a number control. It requires `steps` (an array or a readable) and
`current` (a step id, `nil` or a readable). A step is `{ id, label,
description?, state?, navigable?, enabled? }`. `state` is `complete`,
`current`, `upcoming` or `error`.

- Step ids are nonempty and unique. Labels are nonempty and can repeat.
- `current` alone sets the current step. It places the underline and the
  summary "Step n of m — Label". `state = "current"` is accepted only on the
  step that `current` names.
- A step's `state` sets its cue and its state word: a check for `complete`,
  the error icon for `error`, and otherwise the step number in a circle. Thus
  an errored current step keeps its error cue. The state word shows under the
  label.
- A `current` that names no step shows "No current step". An empty list shows
  "No steps" and has no Steps button.
- A step is a Button only when it is `navigable`, it is not disabled, and you
  supply `onSelect`. Other steps are plain content and never selectable. A
  press on a permitted step calls `onSelect(id)` once. The control never
  writes `current`. Thus a refused step changes nothing.
- Every step has the same inset as a Button of its `controlSize`, whether it
  is a Button or plain content. Thus every cue starts at the same place.
- `sizing` is `fill` (default, every step gets an equal share of the row) or
  `hug` (each step gets its own width). `listLabel` (default
  "Steps"), `controlSize`, `enabled` and `controls` are optional. The control
  sets `controls.diagnostics()`.

A malformed snapshot at construction causes an error. A later malformed
snapshot keeps the last legal one, with a warning and a diagnostic line. The
control measures its root width. With `fill` it compares that width with the
widest step text times the step count. With `hug` it compares that width with
the laid-out row (the row `UIListLayout.AbsoluteContentSize`). When the steps
do not fit, the row changes to the summary and a Steps Menu. The menu lists every
step. Permitted steps select through the same `onSelect`. The menu closes
when your `current` changes, so a refused step leaves it open. The number
circle keeps an aspect ratio of 1 at every text size. The row stretches its
cells to one height with a native `ItemLineAlignment`.

The underline is a `facet-selection-indicator` frame. It moves to the new
current step on a spring. Reduced motion places it immediately. Its position
and width are fractions of the row width, so an ancestor `UIScale` (the TV
scale) does not scale it twice. The root has
the attributes `FacetCurrent`, `FacetSummary`, `FacetForm` (`row` or
`summary`) and `FacetListOpen`.
