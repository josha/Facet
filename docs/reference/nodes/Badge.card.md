# Badge.card

Show a short status label.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Badge "Badge" { label = "New" }
```

Key options: `label`, `status`, `icon`, `appearance`.

Keep the label short.

A bound `label` that becomes `nil` or empty hides the Badge until it has text
again, so you do not need to hide it yourself.

Related controls: [Controls](Controls.md).

Open:

- [Badge.reference](Badge.reference.md)
