# Facet documentation

Use `UI.shake(targets, options?)` for brief feedback on existing tile faces.
`targets` is a `{ GuiObject }` array or a readable array. `Facet.ShakeOptions`
accepts an optional nonnegative `intensity` multiplier, default `1`.
The returned `Facet.Sequence` has `play`, `cancel`, `finish`, `running` and
`completed`. See [effect sequences](nodes/Effect-sequences.md) for restoration,
motion policy and theme tokens.

Open the [documentation map](nodes/Map.md).

`Facet.design()` loads the design kit on first use: `Design` (Compose Design), `library(context)`, `controls` and `seeds`. A game that does not author designs never loads it.
See [Design library](nodes/Design-library.md).
Run `lute run tools/facet docs` to read the map.

`Facet.controls(runtime, options?)` returns controls for a Compose Roblox runtime.
Without options, it returns the controls provided for that runtime in the
current Compose owner or a parent owner. If no provider exists, it makes fresh
controls. Explicit options, including `{}`, always make fresh controls.

`UI.provide(body)` provides `UI` while `body()` runs and to its descendant
Compose owners. It returns the results of `body()`. A nested provider replaces
the controls for the same runtime within its scope. Controls for other runtimes
stay available. The provider uses the Compose module that made `UI`.

`Facet.app` provides `app.UI` to mounted components and presented content.
For a direct Compose mount, call the provider inside the mount:

```luau
local UI = Facet.controls(runtime, { theme = Facet.themes.neutralPackage() })
local function PortablePanel()
    local inherited = Facet.controls(runtime)
    return inherited.Button { label = "Continue" }
end
local stop = runtime.mount(function()
    return UI.provide(PortablePanel)
end, playerGui)
```

`PortablePanel` can call `Facet.controls(runtime)` to get the same controls
object, with its theme, translator, motion level, text preference, viewport
and overlay host configuration. The provider does not install a StyleSheet.

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
