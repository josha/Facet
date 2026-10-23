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
For pointer-driven transitions, bind a nullable Compose cell to
`Transition.progress`; native drag input holds it and clearing it resumes
the control's settlement.

Use [ButtonGuide](nodes/ButtonGuide.reference.md) for a console button legend
of commands that have no control of their own. `Facet.ButtonGuideProps` types
the control and `Facet.ButtonGuideEntry` types one entry. The Sheet `guide`
option places one on the sheet's bottom edge, and the `buttonGuides` app
option lets players hide every guide.
