# Tasks.shop

Shop.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app({})
local C, UI = Facet.Compose, app.UI
type Item = { id: string, name: string, price: number }
local coins, owned = C.cell(300), C.cell({} :: { [string]: boolean })
local buy = assert(game.ReplicatedStorage:FindFirstChild("Purchase")) :: RemoteFunction
app.mount(function()
  local env = UI.environment()
  local spec: Facet.KeyedCollectionSpec<Item, string> = {
    from = { { id = "kart", name = "Kart", price = 250 }, { id = "boots", name = "Boots", price = 90 } },
    key = "id",
    mode = "all", hug = true, measure = true, minColumnWidth = env.scaled(220),
    itemSize = env.scaled(132), gap = env.scaled(16),
    render = function(row: Facet.Readable<Item>, _, key)
      return UI.Card(key) {
        title = function(use) return use(row).name end,
        caption = function(use: Facet.Use)
          local price = use(row).price
          local need = price - use(coins)
          return `{price} Coins` .. (if not use(owned)[key] and need > 0
            then ` · Need {need} more` else "")
        end,
        primaryAction = {
          label = function(use) return if use(owned)[key] then "Owned" else "Buy" end,
          enabled = function(use) return not use(owned)[key] end,
          onActivate = function()
            if buy:InvokeServer(key).accepted then
              owned:update(function(v) v = table.clone(v) v[key] = true return v end)
            end
          end,
        },
      }
    end,
  }
  return UI.Sheet { title = "Shop", width = "wide", isPresented = C.cell(true), detents = { "hug" },
    content = function()
      return UI.VStack "ShopBody" { width = "fill", UI.VirtualGrid(spec) }
    end }
end)
```

The items share the width and wrap on a narrow screen; size the grid, not
the cards ([sizing](VirtualList-and-VirtualGrid.sizing.md)).
[Purchase](Tasks.purchase.md).
