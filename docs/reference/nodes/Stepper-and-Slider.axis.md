# Stepper-and-Slider.axis

- `axis`: `x` (the default) or `y`. A `y` track runs from bottom to top. Its
  arrows are Up and Down, and Left and Right do not change it. The arrow that
  moves the selection onto a slider does not also change the value.
- `range`: `value` holds `{ lower, upper }`. Each change calls
  `onChange(pair, { thumb = "lower" | "upper" })`, and each completed gesture
  calls `onCommit(pair, { thumb })` once. The two handles, `HandleLower` and
  `HandleUpper`, are 44 by 44 touch targets, and the fill spans between
  them. The handles never cross. A drag keeps the handle that it started
  with. A press on the track moves the nearer handle. For coincident handles,
  a press below the pair moves the lower one and a press above moves the upper
  one. The range Slider is one selection stop. The selection always lands on
  the lower handle; A (gamepad) or Return (keyboard) switches the handle that
  the arrows and the left stick move, and the arrows stay on that handle when
  `minGap` stops the move. The focus look is drawn on the handle being moved,
  and the Slider's `adjusting` attribute (`lower` or `upper`) and accessible
  label name it. A pair that
  is not legal at construction causes an error. A pair that becomes illegal
  later is not painted or written back: the control keeps the last legal pair
  and adds a line to the `diagnostics` attribute.
- `minGap`: a number from 0 (the default) to the width of the range. It is the
  least distance between the handles.
- `thumb`: `always` (the default), `auto` or `none`. `auto` shows the handle on
  hover, selection, drag and with touch input. `none` never shows it. Input
  and the readout do not change.
- `thumbContent(info)`: builds the knob once for each handle.
  `info = { thumb, value, fraction, dragging, enabled }`. `thumb` is `value`,
  `lower` or `upper`. The other four are readables. The knob has no
  `sliderThumb` art and grows from 24 by 24 to fit its content. You cannot
  use it with `thumbImage`.
- `trackContent()`: builds a track node once, for example a colour ramp. It
  replaces the rail and the fill, and fills the track. You cannot use it with
  `trackImage`.
- `rotation`: degrees, or a readable of them. It turns the painted track only.
  The control turns a press back by the same angle, so it reads the value that the
  upright track reads. The label and the readout stay upright.
- `controlSize`: `xsmall`, `compact`, `regular` or `large`. It sets the painted
  track thickness (3, 4, 6 or 8 pixels). The track stays 44 pixels thick as a target.
  The rung also sets the thumb. The thumb is 24 pixels plus the rung's icon size
  less the `regular` icon size, so `regular` keeps the 24 pixel thumb.
