# StepIndicator.card

Show progress through named steps.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.StepIndicator "Setup" { steps = { { id = "name", label = "Name" } }, current = "name" }
```

Key options: `steps`, `current`, `onSelect`.

A current id must name a declared step.

Related controls: [Controls](Controls.md).

Open:

- [StepIndicator.reference](StepIndicator.reference.md)
