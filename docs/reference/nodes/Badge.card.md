# Badge.card

Show a short status label.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Badge "Badge" { label = "New" }
```

Key options: `label`, `status`, `icon`, `appearance`.

Keep the label short. To put a dot or a count on the corner of a Button, use
[badged](badged.md). Put a word, such as Ready, in the Button label.

A bound `label` that becomes `nil` or empty hides the Badge unless it has an
`icon` and accessible `name`. Text arriving later shows it again.

Related controls: [Controls](Controls.md).

Open:

- [Badge.reference](Badge.reference.md)
