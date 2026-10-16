# StepIndicator.card

Show progress through named steps.

Inside an app mount, set `local UI = app.UI`.

```luau
local steps: { Facet.Step } = { { id = "name", label = "Name" } }
UI.StepIndicator "Setup" { steps = steps, current = "name" }
```

Key options: `steps`, `current`, `onSelect`.

A current id must name a declared step.

Related controls: [Controls](Controls.md).

Open:

- [StepIndicator.reference](StepIndicator.reference.md)
