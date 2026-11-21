# Pagination.card

Move through a paged result.

Inside an app mount, set `local UI = app.UI`.

```luau
local page = Facet.Compose.cell(1)
UI.Pagination "Pages" { page = page, pageCount = 3, onChange = function(nextPage) page:set(nextPage) end }
```

Key options: `page`, `onChange`, `pageCount`, `form`, `label`.

The game fetches and validates the selected page.

To step through a short set, such as cars, use `form = "step"`. The row is
Previous, a label and Next, and it hugs:

```luau
local names = { "Comet GT", "Dune Runner", "Atlas V8" }
local car = Facet.Compose.cell(1)
UI.Pagination "CarPicker" { page = car, pageCount = #names, form = "step",
	label = function(index) return names[index] end,
	onChange = function(index) car:set(index) end }
```

Related controls: [Controls](Controls.md).

Open:

- [Pagination.reference](Pagination.reference.md)
