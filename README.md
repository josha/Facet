# Facet

Facet supplies Roblox UI controls over Compose and the engine. Compose constructs
and owns native Instances, bindings, collections and motion. Roblox performs
layout, text editing, scrolling, selection and styling. Facet adds control behavior
and adaptive presentation.

There is one composition path for UI and embedded 3D. Create a Compose Roblox
runtime, obtain Facet controls for that runtime, and mount into an ordinary native
target. Control roots are Instances; native property names and Compose structural
operations are available directly.

## A working screen

Enable `Workspace.PlayerScriptsUseInputActionSystem` in the place. Mount Facet
under ReplicatedStorage and place this LocalScript in StarterPlayerScripts.

```luau
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local UI = Facet.controls(runtime)
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")

local stop = runtime.mount(function()
    local count = Compose.cell(0)
    local sheet = Facet.themes.createStyleSheet(runtime)
    return Host.ScreenGui {
        Name = "Counter", ResetOnSpawn = false,
        sheet,
        Host.StyleLink { StyleSheet = Compose.static(sheet) },
        Host.Frame {
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(320, 120),
            Host.UIListLayout { Padding = UDim.new(0, 8) },
            UI.Label {
                label = function(use) return `Clicked {use(count)} times` end,
            },
            UI.Button {
                label = "Add one",
                onActivate = function() count:update(function(n) return n + 1 end) end,
            },
        },
    }
end, playerGui)

script.Destroying:Connect(function()
    stop()
    runtime:dispose()
end)
```

## Working in this repository

`tools/verify.sh full` runs the current architecture's verification. Use
`tools/bench.sh` for benchmarks and `tools/package.sh build` followed by
`tools/package.sh status` to inspect the distributable locally.

Start with the [guide](docs/guide/README.md),
[public API](docs/reference/api.md), and [contribution workflow](CONTRIBUTING.md).
The gallery and virtual monitors are maintained examples. Package installation
and publishing policy live in [package/README.md](package/README.md).
