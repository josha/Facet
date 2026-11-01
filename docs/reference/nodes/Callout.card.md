# Callout.card

Attach guidance to a control.

Inside an app mount, set `local UI = app.UI`.

```luau
local anchor = UI.Button "Play" { label = "Play" }
local help = UI.Callout "Help" {
  anchor = anchor, title = "Start here", closeButton = true,
  content = function()
    return UI.Text { text = "Try the action.", wrap = true, Size = UDim2.fromScale(1, 0) }
  end,
  actions = { { id = "Try", label = "Try", onActivate = function() print("Try") end } },
  onRetire = function(reason) print(reason) end,
}
UI.VStack "Prompt" { anchor, help }
```

`actions` takes one or two commands. Each action retires this Callout.
For a sequence, use Back and Next with `closeButton` for dismissal.
The model owns the step. Mount a new Callout when the step changes.

Open [Callout.reference](Callout.reference.md) for options.
