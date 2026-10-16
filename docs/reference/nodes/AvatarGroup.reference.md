# AvatarGroup

| Control | Main contract |
|---|---|
| `AvatarGroup` | `items` with id, name, image, userId, icon and presence, and an optional `resource` function that returns an `ImageResource`. max (4); stacked or spread layout; count or ellipsis overflow; onOverflow; diameter or controlSize. A stacked group has the `facet-avatar-stack` tag, and the theme draws a surface ring around each face. The faces take no input. The overflow chip is the only target: an `OverflowGap` keeps it clear of the overlapping faces, and with touch or a gamepad it is at least `targetSizes.minimum` on both axes. The group binds no gamepad button, so ButtonB reaches the screen. |
