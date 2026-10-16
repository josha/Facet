# Chip.card

Choose or remove a compact item.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Chip "Chip" { label = "Ready", selected = Facet.Compose.cell(false) }
```

Key options: `label`, `selected`, `onChange`, `onRemove`.

Choose one binding shape.

Related controls: [Controls](Controls.md).

Open:

- [Chip-and-ShortcutHint](Chip-and-ShortcutHint.md)
