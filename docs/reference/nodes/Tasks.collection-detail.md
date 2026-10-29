# Tasks.collection-detail

Select one key. [Art](Stage.reference.md) fills its parent.

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
	local env = UI.environment()
	local spec: Facet.KeyedCollectionSpec<Item, string> = {
		from = items, key = "id", selection = selected,
		minColumnWidth = env.scaled(160), minColumns = 2, itemSize = env.scaled(190),
		measure = true, gap = env.scaled(16), Size = UDim2.fromScale(1, 1),
		onActivate = function() column:set("detail") end,
		render = function(row)
			return UI.Card {
				title = function(use) return use(row).name end,
				caption = function(use) return use(row).terms end,
				artwork = function() return art(row) end,
			}
		end,
	}
	return UI.NavigationSplitView {
		preferredCompactColumn = column, resizable = false, detailLabel = false, compactBack = back,
		sidebar = function() return UI.VirtualGrid(spec) end,
		detail = function()
			return UI.VStack({
				width = "fill", height = "fill", gap = "s", padding = "m",
				UI.Text { textRole = "heading", wrap = true, text = function(use) return use(chosen).name end },
				UI.ZStack({ width = "fill", height = "fill", UI.fill(), art(chosen) } :: Facet.ZStackProps),
				UI.Text { wrap = true, text = function(use) return use(chosen).terms end },
				UI.Button { label = action, appearance = "emphasis", onActivate = function() commit(chosen:peek()) end },
			} :: Facet.StackProps)
		end,
	}
end
```

[Purchase](Tasks.purchase.md).
