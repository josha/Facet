# Tasks.notices

Show a persistent notice and a transient result.

Controls: Screen, VStack, Notice, Toast.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI

app.mount(function()
    return UI.Screen "Root" {
        UI.VStack "Status" {
            width = "fill", gap = "s",
            UI.Notice "Network" { message = "Connection restored", severity = "success" },
            UI.Toast "Saved" { message = "Settings saved", key = "save" },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Mount an unbound Toast once per result. For a bound Toast that can close, provide onPresentedChange. Use Notice for status that stays visible.

Open:

- [Notice.card](Notice.card.md)
- [Toast.card](Toast.card.md)
