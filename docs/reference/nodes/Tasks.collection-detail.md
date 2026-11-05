# Tasks.collection-detail

Bound both axes; scroll within the selected detail.
The sample assumes a small subject. [3D preview](Stage.card.md).

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
type Item = { id: string, name: string, terms: string }
local function browse(app: Facet.App, items: { Item }, selected: Facet.Value<{ [string]: boolean }>,
  art: (Facet.ReadOnlyValue<Item>) -> GuiObject, action: string, commit: (Item) -> (),
  back: Facet.Value<boolean>): Frame
  local C, UI = Facet.Compose, app.UI
  local column = C.cell("sidebar" :: "sidebar" | "detail")
  local chosen = C.formula(function(use: Facet.Use): Item
    for _, item in items do if use(selected)[item.id] then return item end end
    error("No item")
  end)
  local spec: Facet.KeyedCollectionSpec<Item, string> = {
    from = items, key = "id", selection = selected, minColumnWidth = 160,
    itemSize = 190, measure = true, Size = UDim2.fromScale(1, 1),
    onActivate = function() column:set("detail") end,
    render = function(row)
      return UI.Card {
        title = function(use) return use(row).name end,
        artwork = function() return art(row) end,
      }
    end,
  }
  return UI.NavigationSplitView {
    preferredCompactColumn = column, resizable = false, detailLabel = false, compactBack = back,
    sidebar = function() return UI.VirtualGrid(spec) end,
    detail = function()
      return UI.ScrollView "SelectedDetail" {
        width = "fill", height = "fill", gap = "s", padding = "s",
        UI.Text { textRole = "heading", wrap = true, text = function(use) return use(chosen).name end },
        UI.ZStack { width = "fill", height = 160, art(chosen) },
        UI.Text { wrap = true, text = function(use) return use(chosen).terms end },
        UI.Button { label = action, appearance = "emphasis", onActivate = function() commit(chosen:peek()) end },
      }
    end,
    UI.fill(),
  }
end
```

[Purchase](Tasks.purchase.md). [Short layouts](Collection-layout.md).
