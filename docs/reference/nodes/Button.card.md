# Button.card

Run a player action.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Button "Button" { label = "Save", onActivate = function() print("Save") end }
```

Key options: `label`, `role`, `appearance`, `enabled`, `busy`.

Use onActivate for activation.

Related controls: [Controls](Controls.md).

Open:

- [Button.reference](Button.reference.md)
