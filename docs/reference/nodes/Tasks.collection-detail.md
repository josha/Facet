# Tasks.collection-detail

Call inside the mount. Compact panes have Back.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
type Item = { id: string, name: string, terms: string }
local function browse(app: Facet.App, items: { Item },
  artwork: (Facet.Readable<Item>) -> GuiObject, action: string, activate: (Item) -> ()): Frame
  local C, UI = Facet.Compose, app.UI
  local chosen = C.cell(items[1])
  local column = C.cell("sidebar" :: "sidebar" | "detail")
  local env = UI.environment()
  local spec: Facet.KeyedCollectionSpec<Item, string> = {
    from = items, key = "id", minColumnWidth = env.scaled(160),
    itemSize = env.scaled(190), measure = true, gap = env.scaled(16),
    Size = UDim2.fromScale(1, 1),
    onActivate = function(item) chosen:set(item) column:set("detail") end,
    render = function(row)
      return UI.Card {
        title = function(use) return use(row).name end,
        caption = function(use) return use(row).terms end,
        artwork = function() return artwork(row) end,
      }
    end,
  }
  return UI.NavigationSplitView {
    preferredCompactColumn = column, resizable = false,
    sidebar = function() return UI.VirtualGrid(spec) end,
    detail = function()
      local preview: Facet.ZStackProps = { width = "fill", height = "fill", UI.fill(), artwork(chosen) }
      local detail: Facet.StackProps = {
      width = "fill", height = "fill", gap = "s", padding = "m",
      UI.Text { textRole = "heading", wrap = true, text = function(use) return use(chosen).name end },
      UI.ZStack(preview),
      UI.Text { wrap = true, text = function(use) return use(chosen).terms end },
      UI.Button { label = action, appearance = "emphasis",
        onActivate = function() activate(chosen:peek()) end },
      }
      return UI.VStack(detail)
    end,
  }
end
```

Supply nonempty items and [art](Stage.card.md).
See [purchase state](Tasks.purchase.md) and [sizing](VirtualList-and-VirtualGrid.sizing.md).
