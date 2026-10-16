# Travel.card

Move one visual between native slots.

Inside an app mount, set `local UI = app.UI`.

```luau
local slot = UI.VStack "Slot" {}
UI.Travel "Item" { destination = slot, content = function() return UI.Text { text = "Item" } end }
```

Key options: `destination`, `content`, `motion`, `onLanded`.

Keep the destination slot mounted.

Related controls: [Controls](Controls.md).

Open:

- [Travel.reference](Travel.reference.md)
