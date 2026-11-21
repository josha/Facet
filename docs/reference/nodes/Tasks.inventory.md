# Tasks.inventory

Show a few items, each with a picture and its action.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
type Item = { id: string, name: string, art: string, note: string, action: string? }
local function bag(app: Facet.App, open: Facet.Value<boolean>, owned: { Item }, shop: { Item },
  act: (Item) -> ()): Frame
  local UI = app.UI
  local tab = C.cell("owned")
  local tabs: { Facet.PickerOption<string> } = {
    { value = "owned", label = "Inventory" }, { value = "shop", label = "Shop" } }
  local function cards(items: { Item }): Frame
    local list: { Instance } = {}
    for _, item in items do
      table.insert(list, UI.Card(item.id) {
        title = item.name, caption = item.note, glyph = item.art, layout = "row",
        reveal = "always",
        primaryAction = if item.action
          then { label = item.action, onActivate = function() act(item) end } else nil,
      })
    end
    return UI.Grid { gap = "s", minCellWidth = 200, table.unpack(list) }
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
on the action shows what the player cannot buy. Keep `note` short.
`layout = "row"` puts the picture beside the text, so the bag fits a phone in
landscape. With `minCellWidth`, the Grid shows as many columns as fit the
panel, and its cells take the height of the tallest Card. [Confirm](Tasks.confirm.md) a purchase.
