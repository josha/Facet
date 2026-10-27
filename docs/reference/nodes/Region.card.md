# Region.card

Rank a HUD group at a screen edge.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Region "Region" { zone = "topRight", rank = 1, UI.Text { text = "Ready" } }
```

Key options: `zone`, `rank`, `mayDrop`.

Put Region inside Composition.

Related controls: [Controls](Controls.md).

Open:

- [Composition.reference](Composition.reference.md)
