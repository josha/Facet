# ButtonGuide.card

Show a console button legend for commands without a control of their own.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.ButtonGuide "ButtonGuide" { entries = { { keys = { { "LB" }, { "RB" } }, label = "Tabs" } } }
```

Key options: `entries`, `inputs`.

A guide is a readout, never a focus stop. It shows for a gamepad by default.
Keep it to about four entries in button order.

Related controls: [Controls](Controls.md).

Open:

- [ButtonGuide.reference](ButtonGuide.reference.md)
- [Sheet.guide](Sheet.guide.md)
