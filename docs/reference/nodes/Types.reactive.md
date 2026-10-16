# Reactive property types

<!-- aliases: Reactive type errors | Readable | Facet.Use -->

Annotate a property callback with `Facet.Use` when it reads cells of different types.

```luau
local count = Facet.Compose.cell(100)
UI.Text { text = function(use: Facet.Use): string
    return Facet.format.grouped(use(count))
end }
```

Require the Facet root as `local Facet` in each module that uses its exported types.
Read a cell with `use(cell)` in a property callback. Use `cell:peek()` in an
event handler. Use `cell:set(value)` to write it.

A writable optional value needs an optional initial type before `Compose.cell`:
`local initial: Facet.CivilDate? = nil`. A nonoptional cell cannot accept nil.
For a read-only optional property, return the cell value from an annotated callback.

Give option lists their public type before passing them to a control:
`local options: { Facet.PickerOption<string> } = { ... }`.
Give a collection spec `Facet.KeyedCollectionSpec<Item, string>` so the checker
can report the wrong field. Native properties take native values, cells or
property callbacks; keep the same value type in every branch.

Open:

- [Types](Types.md)
- [Tasks.hud](Tasks.hud.md)
