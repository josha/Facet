# Getting started

Mount the package under ReplicatedStorage. Enable the native input action system
in the place. Create a LocalScript in StarterPlayerScripts.

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

Use Compose cleanup for external subscriptions created inside a component. The
mount stop function releases its component; runtime disposal releases runtime-owned
work. Persistent model cells can be created outside the mounted component.
