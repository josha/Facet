# ShortcutHint.card

Show a native command hint.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.ShortcutHint "ShortcutHint" { keys = { { "E" } } }
```

Key options: `keys`, `action`.

Show the command that the game actually binds.

Related controls: [Controls](Controls.md).

Open:

- [Chip-and-ShortcutHint](Chip-and-ShortcutHint.md)
