# Toggle.card

Change a boolean setting.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Toggle "Toggle" { label = "Music", value = Facet.Compose.cell(true) }
```

Key options: `value`, `onChange`, `presentation`, `row`.

A read-only value needs onChange.

Related controls: [Controls](Controls.md).

Open:

- [Toggle.reference](Toggle.reference.md)
