# Composition.card

Place all HUD regions in one screen.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Composition "Composition" { UI.Region "Status" { zone = "topRight", rank = 1, UI.Text { text = "Ready" } } }
```

Key options: `gap`, `padding`.

Keep HUD groups in one Composition. Facet warns when two Compositions on one
screen place regions in the same zone.
Region forms must be concrete GuiObjects. Put reactive children inside each
stable form instead of passing a factory as the form.
Facet hides the `topbar` strip while the Composition or an ancestor is hidden,
such as a HUD page under a pushed NavigationStack page.

Related controls: [Controls](Controls.md).

Open:

- [Composition.reference](Composition.reference.md)
