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

A reusable helper needs the same argument types as the control. For example,
use `Facet.ValueString` for reactive text, `Facet.TextRole?` for an optional type
role, and `Facet.Activate` for a button callback. A plain `string` permits values
that are not type roles. An untyped collection helper loses its row and key
types; keep `Facet.KeyedCollectionSpec<Item, string>` at that boundary.
Define the state record before creating a cell with empty maps or optional
fields: `local state: Facet.Cell<State> = Facet.Compose.cell(initialState)`.
Check shared helpers before using them across screens so one inference failure
does not become errors throughout the application.

Give a padding table its public type before passing it to a control:
`local inset: Facet.Sides = { top = "xl" }`.

Open:

- [Types](Types.md)
- [Tasks.hud](Tasks.hud.md)
