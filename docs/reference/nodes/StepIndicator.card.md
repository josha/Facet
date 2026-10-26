# StepIndicator.card

Show progress through named steps.

Inside an app mount, set `local UI = app.UI`.

```luau
local steps: { Facet.Step } = { { id = "name", label = "Name" } }
UI.StepIndicator "Setup" { steps = steps, current = "name" }
```

Key options: `steps`, `current`, `onSelect`.

Use a declared current id for an active step. A nil or unknown id shows
"No current step".

Related controls: [Controls](Controls.md).

Open:

- [StepIndicator.reference](StepIndicator.reference.md)
