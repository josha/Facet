# WorldMarker.card

Point to a world target, also from the screen edge when it is off screen.

Inside an app mount, set `local UI = app.UI`.

```luau
local patch = Compose.cell(nil :: BasePart?)
local binding = UI.worldAnchor({ target = patch, offscreen = "retain" })
UI.WorldMarker "Patch" { anchor = binding.anchor, UI.Badge { label = "Golden grass" } }
```

Key options: `anchor`, `edge`, `margin`, `arrow`.

Put the marker in a frame that covers the area it can use, such as the safe
area of the screen.

Related controls: [Controls](Controls.md).

Open:

- [WorldMarker.reference](WorldMarker.reference.md)
