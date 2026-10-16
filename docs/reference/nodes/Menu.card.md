# Menu.card

Open contextual commands.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Menu "Actions" { label = "Actions", items = { { label = "Open", onSelect = function() print("Open") end } } }
```

Key options: `items`, `trigger`, `presentation`, `closeButton`.

Keep a visible Close command for a sheet menu.

Related controls: [Controls](Controls.md).

Open:

- [Menu-and-SplitButton](Menu-and-SplitButton.md)
