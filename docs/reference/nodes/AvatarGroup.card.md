# AvatarGroup.card

Show a group of players.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.AvatarGroup "AvatarGroup" { items = { { id = "guest", name = "Guest", icon = "person" } } }
```

Key options: `items`, `max`, `layout`, `onOverflow`.

Only the overflow chip takes input.

Related controls: [Controls](Controls.md).

Open:

- [AvatarGroup.reference](AvatarGroup.reference.md)
