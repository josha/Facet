# Button.target

Button touch targets and the `target` option.

Facet sets the target floor from the effective input. This is
`UserInputService.PreferredInput`, then the enabled devices. A laptop with a
touch screen that the player uses with a mouse has no touch floor. The floor
is `targetSizes.minimum` (44 pixels in the neutral package).

- A Button with text in its plate (`label`, `subtitle`, `hint` or a row
  title) grows to the floor. When the effective input is touch or a gamepad,
  a `TargetFloor` `UISizeConstraint` keeps the plate at least
  `targetSizes.minimum` on both axes.
- A Button with no text keeps its plate size: an icon, glyph, image or circle
  Button. An empty `label` (`""`) is the same as no label. On touch, an
  invisible `HitTarget` frame extends the hit area around the plate to
  `targetSizes.minimum` on both axes. The plate, its layout size and its paint
  do not change. With a mouse or a gamepad there is no `HitTarget`. A
  reactive label that changes to `""` or from `""` changes the behaviour.
- The `HitTarget` activates the Button. It also starts and stops the repeat
  and the pointer callbacks. Only the plate shows press paint. The `HitTarget`
  is not a selection stop. When the press is on the plate of another Facet
  Button below the `HitTarget`, that Button activates.
- The `HitTarget` can extend over the content near the Button. On touch,
  leave a gap of `targetSizes.minimum` minus the plate size between two small
  icon Buttons. For example, use a gap of 12 pixels between two 32 pixel
  plates. To make the plate larger, set `Size` or a larger `controlSize`.

`target` is `hit` (the default), `thumb` or `inline`.

- `thumb`: on touch, the plate has a `TargetFloor` of
  `UI.environment().thumbTarget` on both axes, with any `controlSize` and
  also with no text. Use it for primary game actions that the player presses
  with a thumb while playing, such as Jump, Drift or Fire. With another input,
  it keeps the usual floor.
- `inline`: for adjacent choices within a compact horizontal control, such as
  page indicators. It keeps the usual minimum height and uses
  `metrics.targetSizes.inline` as the minimum width (24 pixels by default),
  for the plate floor and for the `HitTarget`. Keep the targets separate. The
  inline width must be at least 24 and no larger than `targetSizes.minimum`.
