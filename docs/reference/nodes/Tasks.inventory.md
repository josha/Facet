# Tasks.inventory

Show a few items, each with a picture and its action.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
type Item = { id: string, name: string, art: string, note: string, action: string?,
  ready: Facet.ReadOnlyValue<boolean>? }
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
        reveal = "always", enabled = item.ready,
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

Each item has a picture: `image` for game art, or `glyph` (an icon name or
an emoji), as `art` here. `note` holds only the quantity or the price.
`ready` is false for an item the player cannot buy: `enabled` dims the Card
and its action, so add no "cannot afford" text. `layout = "row"` fits a
phone in landscape. `minCellWidth` gives as many columns as fit. When the
player picks an item and then acts, put that action in the Sheet's
`actions`, below the list.
[Confirm](Tasks.confirm.md) a purchase.
