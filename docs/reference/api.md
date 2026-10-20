# Facet documentation

Open the [documentation map](nodes/Map.md).
Run `lute run tools/facet docs` to read the map.

`Facet.MenuCommand` types a command menu item. `Facet.RadialAction<V>` types a
radial command. See [menu items](nodes/Menu-and-SplitButton.items.md) and
[radial items](nodes/RadialMenu.items.md).

Move an existing live application onto a world surface with
[DiegeticScreen](nodes/DiegeticScreen.reference.md).

Use [SpatialGrid](nodes/SpatialGrid.reference.md) for keyed inventory items
with explicit cell footprints. `Facet.SpatialGridSpec<V, K>` types the control;
`Facet.SpatialPlacement` types both item positions and `DropInfo.placement`.

Use [custom transitions](nodes/Custom-transitions.md) to bind native transforms
to retained presentation progress. `Facet.Transition` and
`Facet.TransitionContext` type the options and callback context.
