# Composition.card

Place all HUD regions in one screen.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Composition "Composition" { UI.Region "Status" { zone = "topRight", rank = 1, UI.Text { text = "Ready" } } }
```

Key options: `gap`, `padding`.

Keep HUD groups in one Composition. Facet warns when two Compositions on one
screen place regions in the same zone.

Related controls: [Controls](Controls.md).

Open:

- [Composition.reference](Composition.reference.md)
