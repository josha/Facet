# DateTimePicker.card

Choose a civil date.

Inside an app mount, set `local UI = app.UI`.

```luau
local today = Facet.Compose.cell({ year = 2000, month = 1, day = 1 })
UI.DateTimePicker "Day" { label = "Day", value = today, onChange = function(value) today:set(value) end }
```

Key options: `value`, `selection`, `min`, `max`, `onCommit`.

A civil date has no time zone.

Related controls: [Controls](Controls.md).

Open:

- [DateTimePicker.reference](DateTimePicker.reference.md)
