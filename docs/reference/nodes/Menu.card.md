# Menu.card

Open contextual commands.

Inside an app mount, set `local UI = app.UI`.

```luau
local activate: () -> () = function() print("Open") end
local command: Facet.MenuCommand = { id = "open", label = "Open", onSelect = activate }
local items: { Facet.MenuItem<string> } = { command }
local spec: Facet.MenuSpec<string> = { label = "Actions", items = items }
UI.Menu "Actions" (spec)
```

Key options: `items`, `trigger`, `presentation`, `closeButton`.

Keep a visible Close command for a sheet menu.

Related controls: [Controls](Controls.md).

Open:

- [Menu-and-SplitButton](Menu-and-SplitButton.md)
