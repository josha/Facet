# ViewThatFits.card

Choose content that fits the room.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.ViewThatFits "ViewThatFits" { UI.Text { text = "Ready" } }
```

Key options: `width`, `height`, numeric children.

Put the smallest form last. A segmented Picker does not fit while its strip
scrolls, so `ViewThatFits { segmented, menu }` shows the menu on a phone.

Related controls: [Controls](Controls.md).

Open:

- [ViewThatFits.reference](ViewThatFits.reference.md)
