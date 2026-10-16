# Pagination.card

Move through a paged result.

Inside an app mount, set `local UI = app.UI`.

```luau
local page = Facet.Compose.cell(1)
UI.Pagination "Pages" { page = page, pageCount = 3, onChange = function(nextPage) page:set(nextPage) end }
```

Key options: `page`, `onChange`, `pageCount`, `form`.

The game fetches and validates the selected page.

Related controls: [Controls](Controls.md).

Open:

- [Pagination.reference](Pagination.reference.md)
