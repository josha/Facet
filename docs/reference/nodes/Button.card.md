# Button.card

Run a player action. Inside an app mount, set `local UI = app.UI`.

```luau
UI.Button "Button" { label = "Save", onActivate = function() print("Save") end }
```

Key options: `label`, `subtitle`, `role`, `appearance`, `enabled`, `busy`.

Use `subtitle` for text inside the plate. `caption` is an external HUD annotation:
it reserves no layout space and can exceed the button width. Do not use it for
record facts. See [record actions](Button.records.md).

Use `align = "stretch"` on a VStack, a `UI.fill()` child in a bounded HStack,
or native `Size` for explicit width. Bounded subtitle buttons wrap and grow.
See [sizing](Button.disclose.md), [labels and input hints](Button.label.md),
[icons](Icons.names.md), and [the full contract](Button.reference.md).
