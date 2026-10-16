# Tasks.shop

Show a shop grid and send a purchase request.

Controls: Screen, VirtualGrid, Button.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
type Item = { id: string, title: string }
local items: { Item } = { { id = "kart", title = "Kart" } }
local entries = Compose.cell(items)
local function purchase(id: string)
    print("Request purchase", id)
end
local spec: Facet.KeyedCollectionSpec<Item, string> = {
    from = entries, key = "id", minColumnWidth = 180, itemSize = 64,
    render = function(current)
        return UI.Button "Buy" {
            label = function(use) return "Buy " .. use(current).title end,
            onActivate = function() purchase(current:peek().id) end,
        }
    end,
}
app.mount(function()
    return UI.Screen "Root" {
        UI.VirtualGrid "Shop" (spec),
    }
end)
script.Destroying:Connect(app.dispose)
```

Replace purchase with the game's server request. The server checks price, balance and ownership. Update the model from its result. Keep durable row state in the model.

Open:

- [Button.card](Button.card.md)
- [VirtualList-and-VirtualGrid](VirtualList-and-VirtualGrid.md)
