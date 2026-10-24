# Label.card

Show an icon with a title.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Label "Label" { title = "Inventory", icon = "person" }
```

Key options: `title`, `icon`, `presentation`.

Use title for the accessible name.
Facet includes game glyphs such as `coin`, `gem`, `star`, `gift`, `chat`, `lock` and `car`.
Take each `icon` name from [Icons.names](Icons.names.md).

Related controls: [Controls](Controls.md).

Open:

- [Label.reference](Label.reference.md)
