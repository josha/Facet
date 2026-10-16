# Menu-and-SplitButton.selected

- A level whose `selected` group holds one of its rows opens with the
  selection on that row, and scrolls that row to the center of the list. A
  `checked` item does not move the landing.
- Every row is at least the target size (44) tall, and the label leads the row.
  A row can also have `badge` (a string, a number or a readable, shown as a
  Badge named `Count`), `avatar` (`{ name, image?, userId? }`, a compact
  Avatar that takes no selection), `sectionTitle` (a caption heading before the
  row, never a selection stop) and `shortcutLabel` (display text such as
  "Ctrl+B"). `shortcutLabel` binds no key. Bind the key where the action is.
  Picker passes the option `badge` to its menu rows.
- `controls` is an optional table. The menu sets `controls.diagnostics()`,
  which returns the platform-guidance advice for the current items: a
  submenu two or more levels deep, a level of more than five items, and a
  destructive item that is not the last of its level. Advice never refuses a
  menu.


```lua
UI.Menu {
    trigger = UI.Button "More" { icon = "more", shape = "circle" },
    width = { type = "hug", min = 220, max = 320 },
    onOpen = function() headerPinned:set(true) end,
    onClose = function() headerPinned:set(false) end,
    items = {
        { id = "rename", label = "Rename", onSelect = rename },
        { id = "delete", label = "Delete", role = "destructive", onSelect = delete },
    },
}
```

SplitButton combines a primary `label` and `onActivate` action with the
secondary `items` of the menu. Use it when the secondary operations supplement
one clear primary action.

With a mouse or a gamepad, SplitButton is one control plate with two parts:
the primary action and a narrow chevron segment, joined by a hairline. Only the
outer corners are round. Each part is its own focus stop and is at least 44
pixels. The chevron opens the menu. Its accessible name and help text are
`menuLabel` (default `More options`). A skinned theme paints its `control` art
once across the whole plate. With touch, SplitButton is one button
with a trailing chevron: a tap runs the primary action, and a long press opens
the menu.
