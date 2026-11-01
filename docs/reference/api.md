# Facet documentation

Theme readers accept `Facet.ReadOnlyThemePackage`, the shallow readonly view of
`Facet.ThemePackage`. Theme authoring keeps the mutable package type. A frozen
package does not need a copy before a control reads it.

Use `UI.shake(targets, options?)` for brief feedback on existing tile faces.
`targets` is a `{ GuiObject }` array or a readable array. `Facet.ShakeOptions`
accepts an optional nonnegative `intensity` multiplier, default `1`.
The returned `Facet.Sequence` has `play`, `cancel`, `finish`, `running` and
`completed`. See [effect sequences](nodes/Effect-sequences.md) for restoration,
motion policy and theme tokens.

Open the [documentation map](nodes/Map.md).

`UI.draggable` accepts a GuiObject, BasePart, or Model. For world sources, use
`Facet.WorldDragOptions` in `spec.world`. Targets can supply `worldPlacement`,
which also appears in `DropInfo`. See [world drag and drop](nodes/draggable-and-dropTarget.world.md).
Set target `placement` to supply the same logical `DropInfo.placement` as SpatialGrid.
`UI.gestureArbiter` accepts an Instance surface for shared world and UI claims.

`Facet.design()` returns the design kit: `Design` (Compose Design), `library(context)`, `controls`, `seeds` and `motion(UI)`. `motion(UI)` gives a library context the `Facet.DesignMotion` that moves designed values and plays designed sequences with the theme's motion. `Facet.DesignSequence` and `Facet.DesignPlayer` type a designed sequence and its player.

`Facet.composeDesign()` returns the `Facet.DesignStudioKit` that the Compose Design Studio plugin opens. It loads the design editor on first use and gives the plugin the Facet controls, the theme StyleSheet around the staged design, Phone, Tablet, Desktop and Console sizes, and Theme and Text size previews. `Facet.DesignField` types one field of a design kind. `Facet.tag(instance, tags)` adds style tags to an instance and returns it; Compose Design emits it for a node's style tags. A game's own design tokens reach the library through `Facet.design().library({ ..., tokens = { path = "T.", require = 'local T = require(...)' } })`: colors, numbers, gaps, padding, widths and heights accept `{ token = "space.md" }`, and the source writes `T.space.md` with the require in its prelude.
See [Design library](nodes/Design-library.md).
Run `lute run tools/facet docs` to read the map.

`Facet.review.screen(options?)` reads the live screen and reports design
patterns that make it look generic, such as facts joined in one text and
items without a visual. `review.analyze(snapshot)` is the pure form. See
[Review](nodes/Review.md).

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

Use [cameraRig](nodes/cameraRig.reference.md) for bounded room camera input,
reset and focus presets. `Facet.CameraRigOptions`, `Facet.CameraPose` and
`Facet.CameraRig` type its options, pose and Compose-owned handle.

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

Theme authoring types: `Facet.RGB` types a color as `{ r, g, b }`,
`Facet.Gradient` types a theme gradient, `Facet.Rule` types one StyleSheet
rule, and `Facet.AuthoredRuleProperties` types the properties of that rule.
`Facet.WorldAnchorPoint` types one point of a world anchor.
`Facet.SplitColumn` names a NavigationSplitView column: `"sidebar"` or
`"detail"`.
