# Installing without Rojo

Build the local distributable with `tools/package.sh build`, then insert `build/Facet.rbxm` into ReplicatedStorage in Studio. Keep the entire module tree together: Facet includes its pinned Compose snapshot and license notice. Do not copy selected private implementation files into an application.

Enable `Workspace.PlayerScriptsUseInputActionSystem` for the native action controls. Place a LocalScript in StarterPlayerScripts and follow [Getting started](03-getting-started.md). The native runtime mounts your ScreenGui into PlayerGui. Native ScreenGui properties control safe areas, display order and reset behavior.

```luau
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local UI = Facet.controls(runtime)
local stop = runtime.mount(function()
    local sheet = Facet.themes.createStyleSheet(runtime)
    return Host.ScreenGui {
        ResetOnSpawn = false,
        sheet,
        Host.StyleLink { StyleSheet = Compose.static(sheet) },
        UI.Button { label = "Ready", onActivate = function() print("Ready") end },
    }
end, game.Players.LocalPlayer:WaitForChild("PlayerGui"))
script.Destroying:Connect(function()
    stop()
    runtime:dispose()
end)
```

The sheet is a native child; the StyleLink references it to apply themed paint. Keep game models, remotes and assets outside the Facet module tree.

The official Roblox Package asset has not been created unless package metadata says otherwise. Do not invent an asset id or publish a package from a pull request. [Package maintainer instructions](../../package/README.md) describe local build/status and the release-only publish process.
