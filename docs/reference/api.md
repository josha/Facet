# Facet documentation

Start with the [documentation map](nodes/Map.md). It routes each task to a short
recipe or control node. With a shell, run `lute run tools/facet docs` to read the
map, or `lute run tools/facet docs --search TEXT` to find a name. This page
summarizes entry points and types that several nodes share.

`Facet.Compose.cubicBezier(x1, y1, x2, y2)` returns an easing function for
Compose motion. All control points must be finite. The x coordinates must be
in `[0, 1]`; the y coordinates can produce overshoot.

Theme readers accept `Facet.ReadOnlyThemePackage`, the shallow readonly view of
`Facet.ThemePackage`. Theme authoring keeps the mutable package type. A frozen
package does not need a copy before a control reads it.

`UI.Group` returns a native CanvasGroup. Its `groupTransparency` option accepts
a readable number and fades the children together. `Facet.GroupProps` types
its properties. See [Group](nodes/Group.reference.md) for clipping, texture
costs and Design bindings.

Use `UI.shake(targets, options?)` for brief feedback on existing tile faces.
`targets` is a `{ GuiObject }` array or a readable array. `Facet.ShakeOptions`
accepts an optional nonnegative `intensity` multiplier, default `1`.
The returned `Facet.Sequence` has `play`, `cancel`, `finish`, `running` and
`completed`. See [effect sequences](nodes/Effect-sequences.md) for restoration,
motion policy and theme tokens.

`UI.draggable` accepts a GuiObject, BasePart, or Model. For world sources, use
`Facet.WorldDragOptions` in `spec.world`. Targets can supply `worldPlacement`,
which also appears in `DropInfo`. See [world drag and drop](nodes/draggable-and-dropTarget.world.md).
Set target `placement` to supply the same logical `DropInfo.placement` as SpatialGrid.
`UI.gestureArbiter` accepts an Instance surface for shared world and UI claims.

`Facet.design()` returns the design kit: `Design` (Compose Design), `library(context)`, `controls`, `seeds` and `motion(UI)`. `motion(UI)` gives a library context the `Facet.DesignMotion` that moves designed values and plays designed sequences with the theme's motion. `Facet.DesignSequence` and `Facet.DesignPlayer` type a designed sequence and its player.

`Facet.composeDesign(options?)` returns the `Facet.DesignStudioKit` that the Compose Design Studio plugin opens. It loads the design editor on first use and gives the plugin the Facet controls, the theme StyleSheet around the staged design, the Compose device profiles, and Theme and Text size previews. Pass `Facet.DesignStudioOptions` with `registry`, `samples`, and optional `stages`, `themes`, `textSizes` and `capture` to open host Designs in that workspace. `kit.edit(parent, name, link?)` returns the Compose editor as `Facet.DesignStudioEditor`, with `execute`, `canvas`, `session`, `nested` and `dispose`. Commands and visible controls share selections and structured readback. See [host Design workspace](nodes/Design-workspace.md).

`Facet.DesignField` types one field of a design kind. `Facet.tag(instance, tags)` adds style tags to an instance and returns it; Compose Design emits it for a node's style tags. A game's own design tokens reach the library through `Facet.design().library({ ..., tokens = { path = "T.", require = 'local T = require(...)' } })`: colors, numbers, gaps, padding, widths and heights accept `{ token = "space.md" }`, and the source writes `T.space.md` with the require in its prelude.
See [Design library](nodes/Design-library.md).

`Facet.StyleTags` types fixed or live style tags: a string, a string list,
a readable value or a formula. `Facet.tag` replaces its own live tags and
keeps other tags on the instance. Compose owns the live subscription.
`Design.document.bindTags` binds a string or named string list input or row field.

`Facet.DesignContext.space = "3d"` selects Compose Design's 3D stage and an
`Instance` return type for scene documents. With `context.host`, the library
includes native `Model`, `Part`, `PointLight`, `SurfaceLight`, `Texture` and
`Decal` kinds. `Pagination` accepts
positional children, including `UIFlexItem`.

`ZoomView.preferredSelection` sets its optional console entry target. D-pad
or A on the root enters that visible selectable or the selectable nearest
the viewport centre. NavigationSplitView's divider is pointer-only.

`Facet.DesignContext.extension` accepts a `Facet.DesignExtension`. It uses
Compose Design's `extend` API to add consumer kinds and their source prelude.
`Facet.DesignKind` types a kind and its fields. `Facet.DesignResolved` types
the props that its editor builder receives. Pass the same extended library to
emit, parse, render and the Design editor. Existing kind names cannot be replaced.

`Facet.DesignContext.designs` maps kind names to `Facet.DesignRegistered`
entries. Each entry supplies a registered Design contract, source call and
builder. The builder receives the same controls, resolved props and node name.
See [registered Designs](nodes/Design-library.extensions.md#registered-designs).

`Path.points` and `RadialMenu.skin` accept whole theme tokens. A points token
can hold a list whose curve handles come from theme values. A skin token holds
the public RadialMenu skin table. Inline token expressions inside these tables
need Compose Design support; use a whole token for the table.

`Facet.review.screen(options?)` reads the live screen and reports design
patterns that make it look generic, such as facts joined in one text and
items without a visual. `review.analyze(snapshot)` is the pure form. See
[Review](nodes/Review.md).

`Facet.review.screens(targets?, options?)` opens, reviews and closes each target
in name order and returns one text report. With no targets, it finds mounted
Sheets. Pass `{ Name = presentedCell }` or targets with `open()` and optional
`close()` functions for other screens. Run it on the client during Play.
`options.root` selects the review root; `options.settle` sets the wait after
opening, in seconds (default `0.5`). Common build and runtime errors appear
once across the screens. Each target is closed after review.

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

`Facet.RadialMenuBuilder` and `Facet.AlertBuilder` type the direct call of
`UI.RadialMenu` and `UI.Alert`. Luau cannot give an explicit type argument to
an overloaded function, so assign the control to its builder type first:
`local RadialMenu: Facet.RadialMenuBuilder = UI.RadialMenu`, then call
`RadialMenu<<string>>(spec)`.

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

For an action slot, use `UI.Button` with `cooldown = { remaining, total }` and
optional `charges`. `Facet.Cooldown` accepts bound numbers. `total` must be
finite and positive; `remaining` must be finite. The bottom-to-top sweep shows
the clamped remaining fraction. It follows model updates with `motion.fast`
and `motion.easing.trail`, and snaps with reduced motion. It does not run a
game timer or disable the action. Bind `enabled` to the game's availability
rule. `charges` accepts a bound nonnegative integer, including zero. Use
`icon`, `glyph`, and `shortcutHint` for the subject and native InputAction hint.
The sweep uses the theme's scrim paint. Theme rules can target
`.facet-cooldown` and `.facet-charges` for separate paint.

`Facet.HelpSpec` adds optional `rows = { { label, value } }`, `cost`, `cooldown`,
and `flavour` to the existing `title`, required `body`, `shortcut`, `edge`, and
`align`. `Facet.HelpRow` names a row. Text fields accept bound strings. Include
units and labels in cost and cooldown strings. Button Help uses one pattern
for pointer dwell, native selection, and touch long-press. It uses the existing
tooltip theme, safe overlay bounds, edge flipping, and touch clearance.
Keep details brief enough for the viewport; use a Popover or Sheet for long
or interactive content.

`UI.worldSurface(layer, content)` returns a Folder to include in the mounted
tree. `layer` is a native BillboardGui or SurfaceGui. `content` builds one
Instance in a Compose portal to that layer. The portal shares Compose ownership
and the controls provider. Its StyleLink follows the nearest mounted
StyleLink, including StyleSheet replacement. The layer is borrowed: removing
the Folder removes the portal content and link, and leaves the layer standing.
Create a layer through Host in the same tree to give it the same lifetime.
Keep interactive layers in PlayerGui and set Adornee to a world target.
SurfaceGui input also requires the target's CanQuery to be true.

```luau
local Host = runtime.constructors
local layer = Host.BillboardGui {
    Adornee = Compose.static(target), Size = UDim2.fromOffset(220, 48),
    MaxDistance = 80, Active = true,
}
return Host.Folder {
    Compose.portal(playerGui, function() return { layer } end),
    UI.worldSurface(layer, function()
        return UI.Button { label = "Interact", onActivate = interact }
    end),
}
```

Use this inside the existing app mount. Native layers own world projection,
occlusion, distance limits, and input. No Facet projection loop is added.
`examples/performance/world_surfaces.luau` builds a configurable number of
nameplates under one mount and supplies a shared update command. The HUD spec
runs 64 layers and checks teardown. This is a resource and lifecycle scene;
it does not establish a device frame-time budget. Native BillboardGui and
SurfaceGui cache unchanged content; frequent text updates invalidate that
cache. Use bounded distance and update only when the displayed value changes.
