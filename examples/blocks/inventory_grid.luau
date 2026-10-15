--!strict
local FacetTypes = require("../../src")

type Use = FacetTypes.Use
type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type Readable<T> = { peek: (Readable<T>) -> T }
type Item = { id: string, name: string, description: string, slot: string }
type Model = {
	items: Readable<{ Item }>,
	equipped: Readable<{ [string]: string }>,
	equip: (itemId: string, slot: string) -> (),
}

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local Compose = Facet.Compose
	local selection = Compose.cell({} :: { [string]: boolean })
	local selected = Compose.formula(function(use: Use): Item?
		local keys = use(selection)
		for _, item in use(model.items) do
			if keys[item.id] then
				return item
			end
		end
		return nil
	end)
	local itemsSpec: FacetTypes.KeyedCollectionSpec<Item, string> = {
		UI.fill(),
		from = model.items,
		key = "id",
		selection = selection,
		selectionMode = "single",
		minColumnWidth = 180,
		itemSize = 80,
		render = function(current: Readable<Item>): GuiObject
			return UI.Text "ItemName" {
				text = function(use: Use)
					local item = use(current)
					return item.name .. (if use(model.equipped)[item.slot] == item.id then " (Equipped)" else "")
				end,
				textRole = "heading",
			}
		end,
	}
	return UI.Screen "Inventory" {
		padding = "m",
		gap = "m",
		UI.Text "Title" { text = "Inventory", textRole = "title" },
		UI.VirtualGrid "Items"(itemsSpec),
		Compose.show(selected, function()
			return UI.VStack "Details" {
				gap = "s",
				width = "fill",
				UI.Text "Name" {
					text = function(use: Use)
						local item = use(selected)
						return if item then item.name else ""
					end,
					textRole = "heading",
				},
				UI.Text "Description" {
					text = function(use: Use)
						local item = use(selected)
						return if item then item.description else ""
					end,
					wrap = true,
				},
				UI.Text "Slot" {
					text = function(use: Use)
						local item = use(selected)
						return if item then "Slot: " .. item.slot else ""
					end,
					textRole = "caption",
				},
				UI.Button "Equip" {
					label = function(use: Use)
						local item = use(selected)
						return if item and use(model.equipped)[item.slot] == item.id then "Equipped" else "Equip"
					end,
					appearance = "emphasis",
					enabled = function(use: Use)
						local item = use(selected)
						return item ~= nil and use(model.equipped)[item.slot] ~= item.id
					end,
					onActivate = function()
						local item = selected:peek()
						if item then
							model.equip(item.id, item.slot)
						end
					end,
				},
			}
		end),
	}
end
