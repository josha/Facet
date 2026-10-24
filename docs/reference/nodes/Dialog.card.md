# Dialog.card

Show a modal decision.

Inside an app mount, set `local UI = app.UI`.

```luau
local open = Facet.Compose.cell(true)
UI.Dialog "Dialog" { title = "Continue?", isPresented = open, onPresentedChange = function(value) open:set(value) end }
```

Key options: `isPresented`, `title`, `content`, `actions`.

Actions must update game state or presentation explicitly.

Facet gives the `role = "default"` action the `emphasis` appearance, so do not
style the commit action yourself.

Related controls: [Controls](Controls.md).

Open:

- [Dialog.reference](Dialog.reference.md)
