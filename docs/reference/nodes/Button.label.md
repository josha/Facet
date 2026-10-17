# Button.label

`label`, `onActivate`, `enabled`, `disabled` and `busy` define the action. A
disabled or busy button cannot activate. With `repeatDelay` or
`repeatInterval` (the defaults are `0.4` and `0.1` seconds), a held button
activates again after `repeatDelay` and then every `repeatInterval`, for a
mouse, a touch, Return, Space or ButtonA. The repeat follows the frame clock
only while the button is held, and it stops on release, when the pointer
leaves, and when the button is disabled or hidden. The Stepper buttons and the
NumberInput `stepButtons` repeat in this way. `shortcut` supplies
a key code and optional modifiers. `dialogAction` is `default` or `cancel`.

A Button keeps the height of its `controlSize` when its `Size` has no height
and its `AutomaticSize` grows on the Y axis. For example,
`Size = UDim2.new(1, 0, 0, 0)` gives a full-width button of the control height.

`AutoButtonColor` defaults to `false`. The theme owns hover and press paint.
Set it to `true` to use Roblox automatic button coloring.

Presentation options:

`glyph = function(): GuiObject` supplies a native leading visual instead of
`icon`. It runs once in the Button's Compose owner. The native content row
places and sizes the result from the control icon metric; keep `label` for
visible text and `name` for an icon-only accessible name. The result can contain
`UI.Path` controls. The theme applies action, selection and disabled colours
to those paths. Do not set both `glyph` and `icon` or `row.icon`.
