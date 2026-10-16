# RadialMenu.card

Choose a command from a radial menu.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.RadialMenu "Actions" { label = "Actions", items = { { id = "open", label = "Open", onSelect = function() print("Open") end } } }
```

Key options: `items`, `preset`, `anchor`, `holdAction`.

holdAction takes a native InputAction, not an action name.

Related controls: [Controls](Controls.md).

Open:

- [RadialMenu.reference](RadialMenu.reference.md)
