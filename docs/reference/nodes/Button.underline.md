# Button.underline

- `underline`: `always` or `hover`, for a plain text button only. The label
  uses RichText and shows underlined always, or while the pointer is on the
  button, while it is pressed and while it has the gamepad or keyboard
  selection. It is the usual cue on a `link` button. The label text is escaped
  for RichText. An icon, image, row, circle or `compactLabel` button refuses
  `underline`.
- `corners`: `pill` or `square`, or a readable of one.
- `shape`: `rect` or `circle`. A circle with an authored `Size` on one axis
  only keeps that axis and matches the other axis to it.
- `icon` and `trailingIcon`.
- `image`, `imageAspectRatio` (default `16/9`) and `imageFraming` (`fit` or
  `crop`). An image button is 240 pixels wide by default. Its height hugs the
  image and the text. The image fills the width at `imageAspectRatio`, sits
  flush with the top edge and follows the top corners of the plate. The text
  keeps the button side insets and a bottom inset. With an authored fixed
  height, the image fits the space the text leaves at `imageAspectRatio` and
  is centered in it (a native `UIAspectRatioConstraint`, `FitWithinMaxSize`).
- `subtitle` and `row = { title, description, value, icon }`. A row button
  fills its width. It shows `icon` on the leading edge, the title and the
  description, and `value` as secondary text on the trailing edge. When the
  button has `onActivate` and no `trailingIcon`, it also shows a disclosure
  chevron. `value` and `icon` are static strings. `hint` shows as a second
  line of text below the label. See [Settings rows](Settings-rows.md).
- `haptic`: a boolean or a readable. When it is true, the button plays the
  `pressHaptic` of the controls. The default is false. See [Haptics](Haptics.md).
- `help`: one sentence that describes the action. It shows in a small panel
  when a pointer rests on the button for 0.45 seconds with no mouse button
  held. Pointer movement, scrolling and mouse presses reset that delay. It also
  shows when a keyboard or a
  gamepad selection rests on the button for 0.45 seconds, or at once when a
  touch player long-presses the button. The release of that long-press does
  not activate the button, and the next touch anywhere closes the panel. So
  every input can open every help. `help` can also be a table
  `{ title?, body, shortcut?, edge?, align? }`. `title` shows above the body.
  `body` can be empty only when `title` has the words. `shortcut` is a list of
  key chords such as `{ { "Ctrl", "K" }, { "F1" } }`. It is display text only
  and binds no key. `edge` (`top`, `bottom`, `leading` or `trailing`) and
  `align` (`start`, `center` or `end`) place the panel against the button. The
  panel uses the anchored placement of `UI.Popover`. The body fits its text
  up to 264 pixels wide and then wraps. A malformed table stops
  with an error that names `help`.
