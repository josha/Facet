--!strict

local Facet = require(game:GetService("ReplicatedStorage").Facet)

export type InventoryRowsItem = { id: string, name: string, category: string, quantity: number, finish: string }

export type Props = {
	inventoryRows: Facet.ReadOnlyValue<{ InventoryRowsItem }>,
	onChooseFurniture: ((InventoryRowsItem) -> ())?,
	onPlaceFurniture: ((InventoryRowsItem) -> ())?,
}

local _design = {
	contract = {
		inputs = {
			{
				fields = {
					{ id = "id", type = "string" },
					{ id = "name", type = "string" },
					{ id = "category", type = "string" },
					{ id = "quantity", type = "number" },
					{ id = "finish", type = "string" },
				},
				id = "inventoryRows",
				kind = "readable",
				preview = {
					{ category = "Comfort", finish = "Sage", id = "sofa", name = "Leather loveseat", quantity = 0 },
					{ category = "Living", finish = "Sage", id = "table", name = "Oak table", quantity = 0 },
					{ category = "Lighting", finish = "Sage", id = "lamp", name = "Reading lamp", quantity = 0 },
					{ category = "Greenery", finish = "Sage", id = "plant", name = "Monstera", quantity = 0 },
					{ category = "Living", finish = "Sage", id = "shelf", name = "Story shelf", quantity = 0 },
					{ category = "Comfort", finish = "Sage", id = "rug", name = "Sunrise rug", quantity = 0 },
				},
				required = true,
				type = "list",
			},
		},
		outputs = {
			{ id = "onChooseFurniture", row = "inventoryRows" },
			{ id = "onPlaceFurniture", row = "inventoryRows" },
		},
	},
	name = "Furnish",
	state = { { id = "furnitureQuery", initial = "", type = "string" } },
}

local function Furnish(UI: Facet.Controls, props: Props): GuiObject
	local contentPadding: Facet.Sides = { bottom = 24, left = 20, right = 20, top = 20 }
	local state = { furnitureQuery = Facet.Compose.cell "" }
	local furnitureInventoryColumns: { Facet.TableColumn<InventoryRowsItem, string> } = {
		{
			id = "name",
			label = "Furniture",
			minWidth = 180,
			priority = "always",
			render = function(current: Facet.ReadOnlyValue<InventoryRowsItem>)
				return UI.VStack "FurnitureCell" {
					gap = "xs",
					width = "fill",
					UI.Text "FurnitureName" {
						text = function(use)
							return use(current).name
						end,
						textRole = "strong",
						wrap = true,
					},
					UI.Text "FurnitureCategory" {
						role = "secondary",
						text = function(use)
							return use(current).category
						end,
						textRole = "caption",
						wrap = true,
					},
				}
			end,
			sortable = true,
			width = 220,
		},
		{
			id = "quantity",
			label = "Placed",
			priority = 2,
			render = function(current: Facet.ReadOnlyValue<InventoryRowsItem>)
				return UI.Badge "FurnitureQuantity" {
					label = function(use)
						return tostring(use(current).quantity)
					end,
					status = "success",
				}
			end,
			width = 82,
		},
		{
			id = "finish",
			label = "Next finish",
			priority = 1,
			render = function(current: Facet.ReadOnlyValue<InventoryRowsItem>)
				return UI.Text "FurnitureFinish" {
					text = function(use)
						return use(current).finish
					end,
					textRole = "caption",
					wrap = true,
				}
			end,
			width = 110,
		},
	}
	return UI.Screen "Screen" {
		gap = "m",
		UI.ScrollView "Content" {
			gap = "m",
			height = "fill",
			padding = contentPadding,
			width = "fill",
			UI.Text "Eyebrow" {
				role = "secondary",
				text = "FACET HOME",
				textRole = "caption",
				wrap = true,
			},
			UI.Text "Heading" {
				text = "A room that feels like you.",
				textRole = "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary",
				text = "Choose a piece. Find its place. Make it yours.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "Selection" {
				text = "Selected: Cloud sofa · Place 1",
				textRole = "body",
				wrap = true,
			},
			UI.TextInput "FurnitureSearch" {
				clearButton = true,
				placeholder = "Find furniture",
				value = state.furnitureQuery,
			},
			UI.Text "InventoryHeading" {
				text = "YOUR INVENTORY",
				textRole = "body",
				wrap = true,
			},
			UI.Text "InventoryHelp" {
				text = "Select to choose. Swipe or right-click for actions.",
				textRole = "body",
				wrap = true,
			},
			UI.Table "FurnitureInventory" {
				columns = furnitureInventoryColumns,
				height = 340,
				itemSize = 76,
				onActivate = function(...)
					if props.onChooseFurniture then
						props.onChooseFurniture(...)
					end
				end,
				rowActions = function(current: Facet.ReadOnlyValue<InventoryRowsItem>): Facet.RowActionsOptions?
					return {
						fullSwipe = false,
						trailing = {
							{
								id = "choose",
								label = "Choose",
								onActivate = function(...)
									if props.onChooseFurniture then
										props.onChooseFurniture(current:peek())
									end
								end,
							},
							{
								id = "place",
								label = "Place here",
								onActivate = function(...)
									if props.onPlaceFurniture then
										props.onPlaceFurniture(current:peek())
									end
								end,
							},
						},
					}
				end,
				width = "fill",
				from = props.inventoryRows,
				key = "id",
			},
			UI.Text "EmptyFurniture" {
				text = "No furniture matches. Clear your search.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "RoomPlanHeading" {
				text = "ROOM PLAN · Pick a place",
				textRole = "body",
				wrap = true,
			},
			UI.Grid "RoomPlan" {
				cellHeight = 56,
				columns = 3,
				gap = "s",
				UI.Button "Slot_1" {
					appearance = "standard",
					label = "Place 1",
				},
				UI.Button "Slot_2" {
					appearance = "standard",
					label = "Place 2",
				},
				UI.Button "Slot_3" {
					appearance = "standard",
					label = "Place 3",
				},
				UI.Button "Slot_4" {
					appearance = "standard",
					label = "Place 4",
				},
				UI.Button "Slot_5" {
					appearance = "standard",
					label = "Place 5",
				},
				UI.Button "Slot_6" {
					appearance = "standard",
					label = "Place 6",
				},
			},
			UI.Button "Place" {
				appearance = "emphasis",
				label = "Place selected furniture",
			},
			UI.Grid "EditActions" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Rotate" {
					appearance = "standard",
					label = "Rotate",
				},
				UI.Button "Remove" {
					appearance = "standard",
					label = "Remove",
				},
			},
			UI.Text "ColorHeading" {
				text = "FINISH · Choose a palette",
				textRole = "body",
				wrap = true,
			},
			UI.Grid "Palettes" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Palette_sage" {
					appearance = "standard",
					label = "Sage",
				},
				UI.Button "Palette_clay" {
					appearance = "standard",
					label = "Clay",
				},
				UI.Button "Palette_cream" {
					appearance = "standard",
					label = "Cream",
				},
				UI.Button "Palette_midnight" {
					appearance = "standard",
					label = "Midnight",
				},
			},
			UI.Grid "SaveActions" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Save" {
					appearance = "emphasis",
					label = "Save room",
				},
				UI.Button "Restore" {
					appearance = "standard",
					label = "Restore saved room",
				},
			},
		},
	}
end

return Furnish
