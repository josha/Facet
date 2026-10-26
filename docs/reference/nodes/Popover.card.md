# Popover.card

Show anchored content.

Inside an app mount, set `local UI = app.UI`.

```luau
local open = Facet.Compose.cell(true)
UI.Popover "Popover" {
    isPresented = open,
    onPresentedChange = function(next) open:set(next) end,
    source = { rect = { x = 0, y = 0, w = 44, h = 44 } },
    closeButton = true,
    content = function() return UI.Text { text = "Ready" } end,
}
```

Key options: `trigger`, `source`, `edge`, `compact`.

Use a live trigger or a source rectangle. Interactive opening and dismissal
propose a change; the caller must accept it through `onPresentedChange`.

Related controls: [Controls](Controls.md).

Open:

- [Popover.reference](Popover.reference.md)
