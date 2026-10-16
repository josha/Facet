# Slider.card

Choose a value along a track.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Slider "Slider" { value = Facet.Compose.cell(0.5) }
```

Key options: `value`, `min`, `max`, `step`, `onCommit`.

Do not mix scalar and range bindings.

Related controls: [Controls](Controls.md).

Open:

- [Stepper-and-Slider](Stepper-and-Slider.md)
