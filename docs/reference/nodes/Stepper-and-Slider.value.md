# Stepper-and-Slider.value

Both take a numeric `value`, `min` (default `0`), `max` (default `1`), `step`,
`format`, `onChange`, `enabled` and `label`. The maximum must be more than the
minimum. A specified step must be positive. The Stepper step default is `1`.
With `onChange`, the control requests the value and does not write even a
writable cell. Accept the change by writing your model. Without `onChange`,
the control writes its writable value. `onCommit` reports a completed Slider
gesture; it does not mean the game accepted or saved that value.
The Slider default is continuous values.

A Stepper is one selection stop: the Stepper itself takes the selection, Left
and Right change the value, and Up and Down leave it. Its `Decrease` and
`Increase` buttons are not selectable; they still respond to touch and the
mouse.

By default, Slider shows an inline track and a value readout, with an optional
label. Its default native `AutomaticSize.Y` keeps the authored width and fits
the control height. `row` gives a stacked title, description and track. A
Slider row has the `facet-slider-settings` tag and the horizontal padding of a
Button. It shows `row.icon` before the stack, so the Slider row lines up with
Button and Toggle rows.

Slider also supports `onCommit(value)`, `tapToPosition` (default true),
`thumbImage`, `trackImage` and `row`. Dragging uses native drag detection.
Keyboard and gamepad adjustment use the input actions of the control.
The whole Slider (its label, track and value) is one selection stop, so the
engine measures moves from the whole control. Its track and thumb are not
selectable. The focus look is drawn on the 44 by 44 `ThumbStop` frame around
the painted `Thumb` through `FacetFocusPart`, and follows it. With
`thumb = "auto"`, `thumb = "none"` or a `thumbContent` knob, the look is drawn
on the track. A held adjustment repeats after 0.4 seconds, then every 0.1 seconds
(a Stepper's `repeatDelay` and `repeatInterval` set both its held arrow keys
and its held step buttons, with one repeat policy). The
repeat stops when the engine gives the held input to a higher-priority input
context, for example a gameplay binding with `Sink`. The next change needs a
new press.

`contained = true` makes the rail and the fill as thick as the knob, with round
ends, so the knob rides inside the rail. The fill ends at the center of the
knob.

Slider shapes. `axis`, `range`, `minGap` and `thumb` are construction options.
A readable value for one of them causes an error that names the option.
