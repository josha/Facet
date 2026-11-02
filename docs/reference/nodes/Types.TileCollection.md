# Types.TileCollection

<!-- aliases: Typed collections -->

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
callbacks. `SheetDetent` types a sheet detent entry. `Facet.Value<T>`,
`Facet.ReadOnlyValue<T>`, `Facet.Runtime`, `Facet.Owner` and `Facet.Use` are the
Compose types. Collection, menu and picker
contracts keep the item and value types through callbacks. Native properties use
the Roblox property types. For example, `Size` accepts a `UDim2` or a reactive
source of a `UDim2`.

Each `Props` and `Spec` type is one flat table type. It holds the native
properties of the root, the control options and the children. Pass that table
first and an optional name second: `UI.Button "Save" { ... }`.

Use the current Luau solver. For overloaded or generic controls, give the
table its binding or item type on a local, for example
`local props: Facet.MenuSpec<string> = { ... }` and then `UI.Menu(props)`.
Use `Facet.Use` for an explicit reactive callback parameter type.

`Host` types the native constructors, and `Child` types a child entry.

The root module also exports the types of the option values and of the
option parts. Use them to give a local a type without an internal module:
