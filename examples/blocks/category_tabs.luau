--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Item = { id: string, name: string, category: string }
type Model = { items: Readable<{ Item }> }

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local category = Facet.Compose.cell("all")
	local itemsSpec: FacetTypes.KeyedCollectionSpec<Item, string> = {
		UI.fill(),
		from = function(use: Use)
			local selected = use(category)
			local filtered: { Item } = {}
			for _, item in use(model.items) do
				if selected == "all" or item.category == selected then
					table.insert(filtered, item)
				end
			end
			return filtered
		end,
		key = "id",
		minColumnWidth = 180,
		minColumns = 2,
		itemSize = 80,
		scrollReset = category,
		render = function(current: Readable<Item>): GuiObject
			return UI.Text "ItemName" {
				text = function(use: Use)
					return use(current).name
				end,
				textRole = "heading",
			}
		end,
	}
	local options: { FacetTypes.PickerOption<string> } = {
		{ value = "all", label = "All" },
		{ value = "tools", label = "Tools" },
		{ value = "outfits", label = "Outfits" },
	}
	local pickerSpec: FacetTypes.SinglePickerSpec<string> = {
		label = "Category",
		style = "segmented",
		selected = category,
		options = options,
	}
	local picker = (UI.Picker "CategoryTabs" :: unknown) :: (FacetTypes.SinglePickerSpec<string>) -> GuiObject
	return UI.Screen "Categories" {
		padding = "m",
		gap = "m",
		UI.Text "Title" { text = "Collection", textRole = "title" },
		picker(pickerSpec),
		UI.VirtualGrid "Items"(itemsSpec),
	}
end
