# Button.card

Run a player action.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Button "Button" { label = "Save", onActivate = function() print("Save") end }
```

Key options: `label`, `role`, `appearance`, `enabled`, `busy`.

Use onActivate for activation.
Facet shows the input glyph of a `shortcutHint` InputAction on the Button and
outlines `caption` text, so both read over the game view.
To fill a VStack's width, set `align = "stretch"` on that stack.
Use a `UI.fill()` child to share an HStack's width.
Use native `Size` for an explicit width. See [Layout-options](Layout-options.md).

Related controls: [Controls](Controls.md).

Open:

- [Button.reference](Button.reference.md)
