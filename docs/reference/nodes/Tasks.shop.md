# Tasks.shop

A shop grid, one column on phones.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({})
local UI = app.UI
type Item = { id: string, name: string, price: number }
local items: { Item } = { { id = "kart", name = "Kart", price = 250 } }
local open, coins = C.cell(false), C.cell(300)
local owned = C.cell({} :: { [string]: boolean })
local buy = assert(game.ReplicatedStorage:FindFirstChild("Purchase")) :: RemoteFunction
app.mount(function()
  local env = UI.environment()
  local grid: Facet.KeyedCollectionSpec<Item, string> = {
    from = items, key = "id", minColumnWidth = env.scaled(220), itemSize = env.scaled(132),
    render = function(row: Facet.Readable<Item>)
      local it = row:peek()
      local function need(use: Facet.Use): number return math.max(0, it.price - use(coins)) end
      return UI.Card(it.id) { title = it.name,
        caption = function(use: Facet.Use): string
          return `{it.price} Coins` .. (if need(use) > 0 then ` · Need {need(use)} more` else "")
        end,
        primaryAction = {
          label = function(use: Facet.Use): string return if use(owned)[it.id] then "Owned" else "Buy" end,
          enabled = function(use: Facet.Use): boolean return not use(owned)[it.id] end,
          onActivate = function()
            local ok: boolean = buy:InvokeServer(it.id)
            owned:update(function(v) v = table.clone(v) v[it.id] = ok return v end)
          end,
        } }
    end,
  }
  return UI.VStack "Hud" {
    UI.Button "Shop" { label = "Shop", onActivate = function() open:set(true) end },
    UI.Sheet "ShopPanel" { title = "Shop", isPresented = open, closeButton = "Close",
      placement = "center", width = "wide", detents = { "large" },
      content = function() return UI.VirtualGrid "Items"(grid) end },
  }
end)
```

Allow Buy with low funds. [Feedback](Tasks.purchase.md).
Categories use a segmented `Picker`. [Panels](Tasks.sheet.md).
