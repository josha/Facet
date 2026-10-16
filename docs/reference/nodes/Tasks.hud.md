# Tasks.hud

Read currency and open an action from a HUD.

Controls: Screen, Composition, Region, Text, Button.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local coins = Compose.cell(100)
app.mount(function()
    return UI.Screen "Root" {
        UI.Composition "HUD" {
            UI.Region "Wallet" {
                zone = "topRight", rank = 1,
                UI.Text "Coins" { text = function(use) return Facet.format.grouped(use(coins)) end },
                UI.Button "Shop" { label = "Shop", onActivate = function() print("Open shop") end },
            },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

The server owns the balance. Update the cell from its result. Keep HUD groups in one Composition.

Open:

- [Button.card](Button.card.md)
- [Composition.card](Composition.card.md)
- [HUD-formatting](HUD-formatting.md)
