### NumberInput

`UI.NumberInput(spec)` is `UI.TextInput` with `presentation = "number"`. It
refuses `presentation`. `value` (the editable string) and `numericValue` (the
committed number) are cells that you own. Each TextInput option applies. These
options are for the number presentation only:

- `step`: a finite number above zero. The default is 1.
- `precision`: a whole number of decimal places from 0 to 10. A commit and a
  step press round half away from zero. Typing does not round.
- `stepButtons`: two 44 by 44 buttons, `Decrement` and `Increment`, after the
  clear button. They are ordinary focus stops and do not take the arrow keys.
  The control disables a button at the bound that it faces, and disables both
  buttons when the field is read-only or disabled. A press commits with `submit`. With `min` and
  `max`, a press follows the step grid from `min`.
- `prefix` and `suffix`: a string or a readable string beside the TextBox.
  They are not part of the draft.
- `scrub`: a boolean or a readable boolean. A horizontal drag across the
  TextBox changes the number. See below.

Without `precision`, a step press or a scrub rounds to the decimal places of
`step` and `min`. Thus three presses of 0.1 give 0.3.

A commit parses the draft. The default parser accepts an optional sign, digits
and one decimal point only. It refuses an exponent, grouping, hex and blanks.
`Facet.recipes.arithmetic.parse` adds arithmetic. A number outside `min` or
`max` becomes the bound, and `onCommit(number, "clamped")` reports it. A draft
that is empty, a sign alone or a point alone is incomplete. At commit, the
field restores the text of the last committed number and shows no message,
unless `requiredMark` is `required`. A draft that is not a number keeps its
text and shows "Enter a valid number.". `onCommit` receives the number.

`scrub` starts after 6 pixels of mouse travel or 14 pixels of touch travel. A
tap below that distance stays a native tap. A drag that is mostly vertical
stays native. A horizontal drag ends the edit without a commit and restores
the text of the edit start. Then each 8 pixels of total travel is one `step`,
with the rounding and bounds of the step buttons. `onChange` reports each new
text. The release commits once with `submit`. Escape or ButtonB, a change of
PreferredInput, disabling, `readOnly`, `scrub` turning off and disposal cancel
the drag: the number and the text return to the values at the drag start, and
nothing commits. A write of your own to `numericValue` during a drag ends the
drag, and your number stays.

```luau
local draft, laps = Compose.cell("3"), Compose.cell(3)
UI.NumberInput "Laps" {
    value = draft,
    numericValue = laps,
    min = 1,
    max = 99,
    stepButtons = true,
    label = "Laps",
}
```
