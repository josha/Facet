# Tasks.shop

Open a modal shop list with buy actions, owned state and feedback.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
type Item = { id: string, title: string, owned: boolean }
local items: { Item } = { { id = "kart", title = "Kart", owned = false } }
local entries = Compose.cell(items)
local open = Compose.cell(false)
local feedback = Compose.cell("")
local function applyResult(id: string, owned: boolean, message: string)
  entries:update(function(rows)
  local nextRows = table.clone(rows)
  for i, row in rows do
    if row.id == id then nextRows[i] = { id = id, title = row.title, owned = owned } end
  end
  return nextRows
  end)
  feedback:set(message)
end
local function purchase(id: string)
  print("Request purchase", id)
end
local spec: Facet.KeyedCollectionSpec<Item, string> = {
  from = entries, key = "id", itemSize = 64,
  render = function(current)
  return UI.Button "Buy" {
    label = function(use) local row = use(current)
    return row.title .. (if row.owned then " - Owned" else " - Buy") end,
    enabled = function(use) return not use(current).owned end,
    onActivate = function() purchase(current:peek().id) end,
  }
  end,
}
app.mount(function()
  return UI.Screen "Root" {
  UI.Button "Shop" { label = "Shop", onActivate = function() open:set(true) end },
  UI.Sheet "ShopPanel" {
    title = "Shop", isPresented = open, closeButton = "Close",
    content = function() return UI.VStack "Items" {
    width = "fill", gap = "s", align = "stretch",
    UI.Text "Result" { text = feedback, wrap = true },
    UI.VirtualList "Parts" (spec),
    } end,
  },
  }
end)
script.Destroying:Connect(app.dispose)
```

Send purchase to the server. It checks price, balance and ownership.
Call applyResult with its response, including failures.
[Tasks.sheet](Tasks.sheet.md) covers child pages.
