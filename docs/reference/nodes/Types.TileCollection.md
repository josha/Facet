# Types.TileCollection

Types.TileCollection contract and option values.

The pinned Compose module includes `TileCollection`, which owns the nonempty cells
in a world-space tile viewport, and `focusNeighbor`, a pure directional rectangle
search. Their contracts live in the pinned Compose [API reference](../../../skills/compose/references/api.md).
Virtual Monitors uses `TileCollection` for the Facet Flap course.

The exported Luau types include `Facet`, `ComposeModule`, `ComposeRobloxModule`,
`Controls`, `ControlOptions`, `App`, `AppOptions`, `Component`, `ThemePackage`,
`CivilDate`, `CivilRange`, `CivilLocale`, `CivilDateModule`,
and the `Props` and `Spec` contracts of each control. The layout types include
`Space`, `Padding` and `Extent`. `RowActionsOptions` types collection row action
callbacks. `SheetDetent` types a sheet detent entry. `Facet.Cell<T>`,
`Facet.Readable<T>`, `Facet.Runtime`, `Facet.Owner` and `Facet.Use` are the
Compose types. Collection, menu and picker
contracts keep the item and value types through callbacks. Native properties use
the Roblox property types. For example, `Size` accepts a `UDim2` or a reactive
source of a `UDim2`.

Each `Props` and `Spec` type is one flat table type. It holds the native
properties of the root, the control options and the children. In the named
form, `UI.Button "Save" { ... }`, strict mode checks the property table
without casts in both Luau solvers:

- a literal option, such as `textRole = "title"` or `width = "fill"`,
- a callback and a `function(use)` body, without parameter types,
- children of different classes in the same table.

The direct form, `UI.Button { ... }`, calls the overloaded constructor with
the table. Neither solver gives the full props type to a table literal in an
overloaded call. The old solver gives all children the type of the first
child, and it can refuse a literal option. The new solver refuses literal
options. When the table has children of different classes or literal
options, use the named form or give the table a type in a local, for example
`local props: Facet.MenuSpec = { ... }` and then `UI.Menu(props)`.

`Host` types the native constructors, and `Child` types a child entry.

The root module also exports the types of the option values and of the
option parts. Use them to give a local a type without an internal module:
