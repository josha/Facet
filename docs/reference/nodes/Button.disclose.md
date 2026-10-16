# Button.disclose

Button.disclose option values and behavior.

- `disclose`: `true` lets a player read the whole label of a text Button
  that truncates. With an authored width the label keeps one line and
  truncates at the end instead of wrapping. The label shows in the help panel (named `Disclosure`) on the
  same routes as `help`, only while the engine reports that the text does not
  fit (`TextFits`). While it shows, `help` waits: the full value comes first.
- `compactLabel`: an alternative string or readable. The button uses it when a
  plain text button cannot fit its full label. It does not apply to icon, image
  or subtitle buttons.


The pointer callbacks are `onPointerDown`, `onPointerUp` and `onPointerCancel`.
Each callback works alone. `onPointerCancel` runs once when a held pointer
leaves the button, the Button is destroyed, or its Compose owner is disposed.
Cancellation clears the held state and stops repetition before the callback.
A normal release calls `onPointerUp` without a cancellation.

A text Button with a bounded width truncates its label at the end when the
label does not fit its box. A Button whose width follows its label does not
truncate. A text Button or Toggle with an authored `Size` that has a width, and no
authored `AutomaticSize`, wraps its label inside that width and grows in
height. With an authored `TextTruncate` other than `None`, it keeps one line
and truncates instead. An icon Button with an authored width (and no image
or row) keeps that width, and its label truncates at the end. A Button with
`subtitle` or `hint` and an authored width also keeps that width: the label
and the subtitle wrap inside it, and the Button grows in height.
This also applies to a reactive `Size` with `AutomaticSize = None` or `Y`.
Its content stays inside the padding, and the label shrinks before the icon.
An authored width never leaves less than one `control` em for the label inside
the padding and the theme carve: the Button grows to that minimum. The minimum
also holds each icon and the gap after it.
Without an authored width, it hugs its label.
