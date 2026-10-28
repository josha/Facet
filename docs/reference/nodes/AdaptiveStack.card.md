# AdaptiveStack.card

Change the stack axis with available room.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.AdaptiveStack "AdaptiveStack" { UI.Text { text = "Ready" } }
```

Key options: `axis`, `gap`. Without `axis`, the stack is a row while the row fits
and a column when it does not.

Use room and input facts instead of a device branch. Use it for two or three
actions. As a column, every child takes a row, so many short choices such as
swatches, chips or filters belong in `HStack { wrap = true }` instead.

Related controls: [Controls](Controls.md).

Open:

- [AdaptiveStack.reference](AdaptiveStack.reference.md)
