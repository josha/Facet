# Tasks.collection-detail

Bound both axes.

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
    error("No item") end)
  local spec: Facet.KeyedCollectionSpec<Item, string> = {
    from = items, key = "id", selection = selected,
    itemSize = 190, measure = true,
    onActivate = function() column:set("detail") end,
    render = function(row) return UI.Card { title = function(use) return use(row).name end,
      artwork = function() return art(row) end } end,
  }
  return UI.NavigationSplitView {
    preferredCompactColumn = column, resizable = false, detailLabel = false, compactBack = back,
    sidebar = function() return UI.VirtualGrid(spec) end, detail = function()
      local detail = UI.ZStack { width = "fill", height = "fill" }
      local room = UI.environment(detail)
      UI.ScrollView "SelectedDetail" {
        Parent = C.static(detail), width = "fill", height = "fill", gap = "s", padding = "s",
        UI.Text { textRole = "heading", wrap = true, text = function(use) return use(chosen).name end },
        UI.ZStack "Preview" { width = "fill",
        height = function(use: Facet.Use) return math.min(160, use(room.viewportHeight) * 0.3) end,
          art(chosen) },
        UI.Text { wrap = true, text = function(use) return use(chosen).terms end },
        UI.Button { label = action, appearance = "emphasis", onActivate = function() commit(chosen:peek()) end },
      } return detail
    end, UI.fill(),
  }
end
```

[Buy](Tasks.purchase.md). [Layout](Collection-layout.md).
