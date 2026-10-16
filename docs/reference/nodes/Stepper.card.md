# Stepper.card

Change a number in steps.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Stepper "Stepper" { value = Facet.Compose.cell(1) }
```

Key options: `value`, `min`, `max`, `step`.

Use a writable value or provide onChange.

Related controls: [Controls](Controls.md).

Open:

- [Stepper-and-Slider](Stepper-and-Slider.md)
