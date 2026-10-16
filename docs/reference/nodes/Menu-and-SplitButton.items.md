# Menu-and-SplitButton.items

Menu takes an `items` array or readable. It also takes an optional `label` or
`trigger`, `icon`, writable `isPresented`, `enabled`, `onOpen` and `onClose`.

Command menus show a Close icon command in their Sheet presentation. Floating
menus use outside input, Escape, or gamepad B to close. `closeButton = true`
adds the command in either presentation; `false` hides it. Value pickers do not
add this row.

Items have a stable `id` and a `label`. They have optional `icon`, `enabled`,
`hidden`, `children` and `onSelect`. Checked and selected items bind their
writable state. Native input actions supply opening and Back behavior. Nested
menus keep the control-specific navigation of the menu.
