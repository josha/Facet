# Tasks.inspect

Inspection body for [Tasks.pages](Tasks.pages.md). Art fills its parent;
fields hug their content. Identity, terms and commitment remain outside scrolling.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function inspect(app: Facet.App, art: () -> GuiObject, fields: () -> GuiObject,
  title: Facet.ValueString, terms: Facet.ValueString, label: string, commit: () -> ()): Frame
  local C, UI = Facet.Compose, app.UI
  local wide = C.cell(false)
  local function basis(use: Facet.Use): UDim2
    return if use(wide) then UDim2.new(0, 0, 1, 0) else UDim2.new(1, 0, 0, 0)
  end
  local panes = UI.AdaptiveStack "Panes" {
    width = "fill", height = "fill", gap = "m", UI.fill(),
    axis = function(use: Facet.Use): "x" | "y" return if use(wide) then "x" else "y" end,
    UI.ZStack "Art" { Size = basis, AutomaticSize = Enum.AutomaticSize.None, UI.fill(2), art() },
    UI.ScrollView "Fields" { Size = basis, AutomaticSize = Enum.AutomaticSize.None, UI.fill(), fields() },
  }
  local room = UI.environment(panes)
  local threshold = room.scaled(720)
  C.watch(function(use) wide:set(use(room.viewportWidth) >= use(threshold)) end)
  return UI.VStack "Inspector" {
    width = "fill", height = "fill", gap = "s",
    UI.Text { text = title, textRole = "heading", wrap = true },
    panes,
    UI.Text { text = terms, wrap = true },
    UI.Button { label = label, appearance = "emphasis", onActivate = function() commit() end },
  }
end
```

Both panes share remaining room after chrome and commitment; neither has a fixed
minimum height. Resize retains both children. Set the threshold from readable
content. Keep terms short; scroll optional details. Bind art and fields to one draft.

[Stage](Stage.card.md) supplies 3D art. [Collection/detail](Tasks.collection-detail.md)
adds browsing; [purchase](Tasks.purchase.md) handles accepted transactions.
