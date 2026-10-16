# Tasks.settings

Change local settings in a panel.

Controls: Screen, VStack, Toggle, Slider, Divider.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local music = Compose.cell(true)
local volume = Compose.cell(0.5)
app.mount(function()
    return UI.Screen "Root" {
        UI.VStack "Settings" {
            width = "fill", gap = "s", padding = "m",
            UI.Toggle "Music" { label = "Music", value = music },
            UI.Divider "Rule" {},
            UI.Slider "Volume" { value = volume, min = 0, max = 1 },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Persist settings through the game model. Use row and hint for settings with descriptions.

Open:

- [Settings-rows](Settings-rows.md)
- [Slider.card](Slider.card.md)
- [Toggle.card](Toggle.card.md)
