# Tasks.inventory

Show a few items, each with a picture and its action.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
type Item = { id: string, name: string, art: string, note: string, action: string? }
local function bag(app: Facet.App, open: Facet.Value<boolean>, owned: { Item }, shop: { Item },
  act: (Item) -> ()): Frame
  local UI = app.UI
  local env = UI.environment()
  local tab = C.cell("owned")
  local tabs: { Facet.PickerOption<string> } = {
    { value = "owned", label = "Inventory" }, { value = "shop", label = "Shop" } }
  local function cards(items: { Item }): Frame
    local list: { Instance } = {}
    for _, item in items do
      table.insert(list, UI.Card(item.id) {
        title = item.name, caption = item.note, reveal = "always", glyph = item.art,
        primaryAction = if item.action
          then { label = item.action, onActivate = function() act(item) end } else nil,
      })
    end
    return UI.Grid { gap = "s",
      columns = function(use: Facet.Use) return if use(env.isCompact) then 2 else 3 end,
      table.unpack(list) }
  end
  return UI.Sheet "Bag" {
    title = "Bag", isPresented = open, placement = "center", detents = { "hug" },
    content = function()
      return UI.VStack "Body" { width = "fill", gap = "m",
        UI.Picker "Tabs" { selected = tab, options = tabs, style = "segmented" },
        C.switch(tab, { owned = function() return cards(owned) end,
          shop = function() return cards(shop) end }),
      }
    end,
  }
end
```

Each item has a picture: `image` for game art, or `glyph`, a Facet icon name
or an emoji that the Card draws large, as `art` here. `note` holds the quantity or the price. `enabled`
on the action shows what the player cannot buy. A Grid of Cards with no cell
size fits its cells to the cards. [Confirm](Tasks.confirm.md) a purchase.
