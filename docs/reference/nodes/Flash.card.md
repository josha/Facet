# Flash.card

Paint a transient effect over a target.

Inside an app mount, set `local UI = app.UI`.

```luau
local target = UI.Button "Target" { label = "Ready" }
UI.Flash "Pulse" { target = target, progress = 0.5 }
```

Key options: `target`, `progress`, `color`, `mode`.

Compose owns the effect portal. Motion timing belongs to the theme.

Related controls: [Controls](Controls.md).

Open:

- [Effect-sequences](Effect-sequences.md)
