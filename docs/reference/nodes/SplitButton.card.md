# SplitButton.card

Pair a primary action with a menu.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.SplitButton "Save" { label = "Save", onActivate = function() print("Save") end, items = { { label = "Save copy", onSelect = function() print("Copy") end } } }
```

Key options: `label`, `onActivate`, `items`, `menuLabel`.

Give the primary command its own onActivate.

Related controls: [Controls](Controls.md).

Open:

- [Menu-and-SplitButton](Menu-and-SplitButton.md)
