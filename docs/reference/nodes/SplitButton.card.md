# SplitButton.card

Pair a primary action with a menu.

Inside an app mount, set `local UI = app.UI`.

```luau
local activate: () -> () = function() print("Open") end
local command: Facet.MenuCommand = { id = "copy", label = "Save copy", onSelect = activate }
local items: { Facet.MenuItem<string> } = { command }
local spec: Facet.SplitButtonSpec<string> = { label = "Save", onActivate = function() print("Save") end, items = items }
UI.SplitButton "Actions" (spec)
```

Key options: `label`, `onActivate`, `items`, `menuLabel`.

Give the primary command its own onActivate.

Related controls: [Controls](Controls.md).

Open:

- [Menu-and-SplitButton](Menu-and-SplitButton.md)
