# Rating.card

Show or choose a rating.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Rating "Rating" { value = Facet.Compose.cell(3) }
```

Key options: `value`, `count`, `onChange`.

Keep durable ratings in the model.

Related controls: [Controls](Controls.md).

Open:

- [Rating-and-LevelPicker](Rating-and-LevelPicker.md)
