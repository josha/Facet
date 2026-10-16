# Alert.card

Ask for a short decision.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Alert "Alert" { title = "Continue?", isPresented = Facet.Compose.cell(true), actions = { { id = "close", label = "Close", onActivate = function() end } } }
```

Key options: `title`, `actions`, `isPresented`.

Use a typed action array when literal roles need strict types.

Related controls: [Controls](Controls.md).

Open:

- [Alert.reference](Alert.reference.md)
