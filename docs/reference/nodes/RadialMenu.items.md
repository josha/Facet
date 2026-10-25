# RadialMenu.items

The required `items` use the menu item model. The options are:

Use `Facet.RadialAction<string>` for a command and
`{ Facet.RadialItem<string> }` for its list. `Facet.RadialMenuSpec<string>`
accepts command menus without generic inference. Other value types use the
generic constructor overload.

`isPresented`, `label`, `launcher`, `preset`, `distribution`, `navigation`,
`expansion`, `center`, `centerLabel`, `centerContent`, `centerPassThrough`,
`anchor`, `follow`, `clearance`, `ringWidth`, `iconSize`, `contentFit`, `gestureSelection`,
`holdAction`, `enabled`, `scrim`, `onOpen` and `onClose`.

The launcher is a round `more` button whose accessible name is
`Quick actions`. With a `label`, the launcher is a text button that shows the
label, and `icon` adds a glyph to it. `launcher = false` hides it. With a
native GuiObject `anchor`, the launcher sits over the centre of that object.

`holdAction` is a native InputAction Instance that the caller owns. The control
subscribes to its `Pressed` and `Released` events. It does not accept an action
name, and it does not define key bindings. Put InputBindings inside the
InputAction, and put that action inside a native InputContext. Use Host
positional children for this ownership tree.

`completion` sets what item activation does: close, stay, return to the root,
or go back. You can navigate nested items. Checked and selected items update
their model. The geometry is specific to this control. It does not add a second
general layout or input system. A native GuiObject anchor or a projected
screen-point anchor connects the menu to an existing surface.

An open ring is a modal surface on the same layer as Dialog and Menu. It
blocks the page's input but does not dim it by default, as in 0.11.
`scrim` sets how much the open ring dims the page: `"none"` (the default),
`"dark"` or `"light"` (the theme scrim that a Dialog uses). The dark scrim is
black and at least 80 percent opaque (the theme's `scrimOpacity` when that is
higher). A scrim reaches past the ScreenGui's safe-area insets to the screen
edges, the hole included, unless `centerPassThrough` is on. The transparency
preference scales it like every scrim. A still tap outside
the ring closes the menu. A press outside the ring that slides onto a wedge
still selects it. With `centerPassThrough`, the page is not dimmed.

A wedge takes the theme panel paint (`surfaceStrong`) and its label the
content paint. A hovered, focused, checked or selected wedge takes the selected
paint (`controlSelected`), the same state its label shows.
The wedge is the item. Its icon and label are a plate-less `utility` button
with no theme control art, sized to the largest box that fits inside the wedge
and clipped to it.
