# AvatarGroup.card

Show a group of players.

Inside an app mount, set `local UI = app.UI`.

```luau
local items: { Facet.AvatarMember } = { { id = "guest", name = "Guest", icon = "person" } }
UI.AvatarGroup "Players" { items = items }
```

Key options: `items`, `max`, `layout`, `onOverflow`.

Only the overflow chip takes input.

Related controls: [Controls](Controls.md).

Open:

- [AvatarGroup.reference](AvatarGroup.reference.md)
