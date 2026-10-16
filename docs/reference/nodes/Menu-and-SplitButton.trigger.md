# Menu-and-SplitButton.trigger

Menu-and-SplitButton.trigger option values and behavior.

- `trigger` attaches the menu to a node that you make. The node can be any
  GuiObject, or a function that returns one. Menu returns that same node, with
  the input actions and the overlay of the menu attached. Menu adds no wrapper,
  so the layout does not change. The other native properties of the spec, and a
  constructor name, apply to the trigger node. Give `label` and Menu makes a
  plain Button trigger in a `Menu` frame. `label` and `trigger` together cause
  an error.
- A secondary-click menu opens at the pointer, clamped to the available screen.
  Activation and keyboard opening use the trigger. Touch and gamepad retain the
  adaptive sheet presentation.
- `onOpen` runs once each time the menu opens and `onClose` runs once each
  time it closes. This includes a change of `isPresented`, a chosen action, a
  tap outside, Back, a disabled or removed trigger, and unmount.
- Under the `menu` presentation the floating panel is one raised card. The
  panel has the `facet-menu` tag and owns the corner (`radii.panel`), the
  hairline stroke and a raised `UIShadow`. The rows are flat and touch, and a
  hairline (`facet-menu-hairline`) separates each pair of adjacent rows. A
  divider or a section title starts a new group with no hairline. A selected or
  checked row fills with the `accent` of the theme under an `onAccent` label
  and icon. Each theme package must have 4.5:1 contrast for this pair. Under
  `sheet` the rows keep their gaps and have no hairlines.
- Each row of a floating panel is the hit floor high: `targetSizes.minimum`.
  When the theme package declares `targetSizes.pointer` and the input is
  pointer-only (`MouseEnabled`, and neither `TouchEnabled` nor
  `GamepadEnabled`), the rows use that smaller height and get the
  `facet-menu-dense` tag, which removes their vertical padding. The rows grow
  back when touch or a gamepad becomes available, and become dense again when
  the input is pointer-only. A Picker menu uses the same rows.
- `triggers` limits the routes that open the menu. The routes are `activate`,
  `secondary`, `longPress`, `keyboard` and `gamepad`. The default is all five.
- `presentation` is `automatic`, `menu` or `sheet`. `automatic` is a sheet
  when the preferred input is touch or a gamepad, or when the layer is too
  narrow for the open levels side by side, and a floating menu otherwise. So a
  gamepad gets one panel whose submenus replace its rows, not a cascade.
  `backLabel` sets the text of the Back row. In a sheet, a submenu replaces the rows and adds a Back
  row. In a floating menu, a submenu opens as a new level beside its parent
  level, which keeps the open row filled. A floating menu has no Back row.
