# Dialog.card

Show a modal decision.

Inside an app mount, set `local UI = app.UI`.

```luau
local open = Facet.Compose.cell(true)
UI.Dialog "Dialog" { title = "Continue?", isPresented = open, onPresentedChange = function(value) open:set(value) end }
```

Key options: `isPresented`, `title`, `content`, `actions`.

For a navigable form, set `bodyHeight` and `presentation = "inset"`. Put long
content in a ScrollView inside the page. See [bounded sizing](Dialog.sizing.md).

Actions propose closing after their callback unless `keepOpen = true`.
The caller accepts or refuses presentation changes. Keep asynchronous
confirmation open until the game accepts the request.

Facet gives the `role = "default"` action the `emphasis` appearance, so do not
style the commit action yourself.

Related controls: [Controls](Controls.md).

Open:

- [Dialog.reference](Dialog.reference.md)
- [Tasks.confirm](Tasks.confirm.md): a purchase confirmation that stays open until the server answers.
