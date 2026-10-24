# Mounting.AppOptions

Set application options with `AppOptions`.

`AppOptions` accepts every `controls` option (see [Factory options](Factory-options.md))
and these fields:

- `runtime`: a runtime that you own. The app does not dispose it. Give a
  runtime when you test without Roblox.
- `parent`: the default parent of each ScreenGui.
- `name`: the ScreenGui name. The default is `Facet`.
- `screen`: native ScreenGui properties, such as `DisplayOrder`,
  `ScreenInsets` or a reactive `Enabled`. They replace the defaults
  (`Name` from `name`, `ScreenInsets = CoreUISafeInsets`,
  `SafeAreaCompatibility = None`, `ResetOnSpawn = false`,
  `ZIndexBehavior = Sibling`). A [Screen](Screen.reference.md) `surface`
  reaches the glass with these defaults, so a page needs no other value.
- `sheet`: `createStyleSheet` options, such as `theme` for the palette or
  `transition`. The app adds `types` and `motionLevel` when you do not set
  them.

The app gives `theme` to the controls and to the StyleSheet, so you set the
theme one time. Give `buttonGuides` a readable boolean that a player setting
owns; every [ButtonGuide](ButtonGuide.reference.md) reads it.
`component` runs in the owner of the mount. Cells that it makes belong to that
mount. `app.mount` after `app.dispose` stops with an error.

When you need a root that is not a ScreenGui, such as a SurfaceGui, or a
StyleSheet that other roots share, use the runtime directly. These functions are the pieces that
`app` uses:

- `runtime.mount`,
- `runtime.mountFragment`,
- `runtime.decorate`,
- `runtime:dispose`.

`decorate` applies only properties and events. To mount native children, use
`mount` or `mountFragment`. The stop function that a mount returns ends that
mount. Stop the mounts before you dispose the runtime.

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local UI = Facet.controls(runtime)
local stop = runtime.mount(function()
    local sheet = Facet.themes.createStyleSheet(runtime)
    return Host.ScreenGui {
        Name = "Example",
        sheet,
        Host.StyleLink { StyleSheet = Compose.static(sheet) },
        UI.Button { label = "Continue", onActivate = function() print("Continue") end },
    }
end, game.Players.LocalPlayer.PlayerGui)
```
