# RadialMenu.card

Choose a command from a radial menu.

Inside an app mount, set `local UI = app.UI`.

```luau
local activate: () -> () = function() print("Open") end
local command: Facet.RadialAction<string> = { id = "open", label = "Open", onSelect = activate }
local items: { Facet.RadialItem<string> } = { command }
local spec: Facet.RadialMenuSpec<string> = { label = "Actions", items = items }
UI.RadialMenu<<string>>(spec, "Actions")
```

Key options: `items`, `preset`, `anchor`, `holdAction`.

holdAction takes a native InputAction, not an action name.

Related controls: [Controls](Controls.md).

Open:

- [RadialMenu.reference](RadialMenu.reference.md)
