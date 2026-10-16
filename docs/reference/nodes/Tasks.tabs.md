# Tasks.tabs

Switch between peer pages and segmented choices.

Controls: Screen, TabView, Picker, Text.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local tab = Compose.cell("play")
local mode = Compose.cell("solo")
local options: { Facet.PickerOption<string> } = {
    { value = "solo", label = "Solo" }, { value = "team", label = "Team" },
}
local tabs: { Facet.Tab } = {
    { id = "play", label = "Play", content = function()
        return UI.Picker "Mode" { selected = mode, options = options, style = "segmented" }
    end },
    { id = "profile", label = "Profile", content = function() return UI.Text { text = "Profile" } end },
}
app.mount(function()
    return UI.Screen "Root" {
        UI.TabView "Pages" { selection = tab, tabs = tabs },
    }
end)
script.Destroying:Connect(app.dispose)
```

TabView owns page retention, selection restoration and shoulder navigation. Use Picker for a value choice within one page.

Open:

- [Picker.reference](Picker.reference.md)
- [TabView.reference](TabView.reference.md)
