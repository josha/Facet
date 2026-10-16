# Tasks.safe-layout

Keep controls usable with touch and a gamepad.

Controls: Screen, AdaptiveStack, Button, Text.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI

app.mount(function()
    return UI.Screen "Root" {
        UI.AdaptiveStack "Actions" {
            width = "fill", gap = "s", padding = "m",
            UI.Text "Help" { text = "Choose an action", wrap = true },
            UI.Button "Play" { label = "Play", onActivate = function() print("Play") end },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Facet.app sets ScreenGui.ScreenInsets to Enum.ScreenInsets.CoreUISafeInsets and disables fullscreen compatibility expansion. Presented content stays inside the core UI and device safe area. Modal scrim paint covers the full screen; its dismissal button stays inside the safe area. Composition uses GuiService.TopbarInset and Enum.ScreenInsets.TopbarSafeInsets for a topbar region. Native selection and control input handle activation. Use UI.environment for available room and preferred input. Do not branch on the device. Do not bind Escape or gamepad Start.

Open:

- [AdaptiveStack.card](AdaptiveStack.card.md)
- [Screen.card](Screen.card.md)
- [environment](environment.md)
