# Tasks.progress

Show health and remaining round time.

Controls: Screen, VStack, ProgressView, Timer.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local health = Compose.cell(0.8)
local deadline = Compose.cell(os.clock() + 60)
app.mount(function()
    return UI.Screen "Root" {
        UI.VStack "Status" {
            width = "fill", gap = "s",
            UI.ProgressView "Health" { value = health, label = "Health" },
            UI.Timer "Round" { deadline = deadline, now = os.clock },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Use the same clock for the deadline and now. The timer reports display completion. The server owns round state.

Open:

- [ProgressView.card](ProgressView.card.md)
- [Timer.card](Timer.card.md)
