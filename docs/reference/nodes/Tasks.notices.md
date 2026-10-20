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
        },
    }
end)
app.presentToast(function(UI)
    return UI.Text { text = "Settings saved" }
end, { key = "save" })
script.Destroying:Connect(app.dispose)
```

Call `app.presentToast` after the game confirms a result. It owns the toast's
mount and stops it when the toast retires. Its `key` groups repeated results.
The sample shows one confirmed result after mounting the screen.

Use `UI.Toast` when a component owns its presentation. Mount an unbound Toast
once per result; retirement hides its row but keeps its anchor until unmount.
For a bound Toast that can close, provide `onPresentedChange`. Use Notice for
status that stays visible. Localize the sample messages with the game translator.

Open:

- [Notice.card](Notice.card.md)
- [Toast.card](Toast.card.md)
