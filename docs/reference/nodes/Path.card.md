# Path.card

Draw a stroked vector shape.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Path "Path" { points = Facet.pathShapes.ring() }
```

Key options: `points`, `thickness`, `role`, `closed`.

A Path draws a stroke, not a filled area.

Related controls: [Controls](Controls.md).

Open:

- [Path-shapes](Path-shapes.md)
