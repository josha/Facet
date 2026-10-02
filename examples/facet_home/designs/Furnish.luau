--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose

return function(UI: Facet.Controls, data: { [string]: any }?): GuiObject
	local state_n7 = Compose.cell("")
	local columns_n10: { Facet.TableColumn<any, any> } = {
		[1] = {
			["id"] = "name",
			["label"] = "Furniture",
			["minWidth"] = 180,
			["priority"] = "always",
			["render"] = function(current: any)
				return UI.VStack "name" {
					gap = "xs",
					padding = "xs" :: "xs",
					width = "fill" :: "fill",
					UI.Text "FurnitureName" {
						text = function(use: any)
							return tostring(
								if use(current)["name"] == nil then "Sample value" else use(current)["name"]
							)
						end,
						textRole = "strong" :: "strong",
						wrap = true,
					},
					UI.Text "FurnitureCategory" {
						role = "secondary" :: "secondary",
						text = function(use: any)
							return tostring(
								if use(current)["category"] == nil
									then "A little possibility"
									else use(current)["category"]
							)
						end,
						textRole = "caption" :: "caption",
						wrap = true,
					},
				}
			end,
			["sortable"] = true,
			["value"] = function(row: any)
				return row["name"]
			end,
			["width"] = 220,
		},
		[2] = {
			["id"] = "quantity",
			["label"] = "Placed",
			["priority"] = 2,
			["render"] = function(current: any)
				return UI.VStack "quantity" {
					gap = "xs",
					padding = "xs" :: "xs",
					width = "fill" :: "fill",
					UI.Badge "Badge" {
						label = function(use: any)
							return tostring(if use(current)["quantity"] == nil then "0" else use(current)["quantity"])
						end,
						status = "success" :: "success",
					},
				}
			end,
			["value"] = function(row: any)
				return row["quantity"]
			end,
			["width"] = 82,
		},
		[3] = {
			["id"] = "finish",
			["label"] = "Next finish",
			["priority"] = 1,
			["render"] = function(current: any)
				return UI.VStack "finish" {
					gap = "xs",
					padding = "xs" :: "xs",
					width = "fill" :: "fill",
					UI.Text "CellValue" {
						text = function(use: any)
							return tostring(
								if use(current)["finish"] == nil then "Sample value" else use(current)["finish"]
							)
						end,
						textRole = "caption" :: "caption",
						wrap = true,
					},
				}
			end,
			["value"] = function(row: any)
				return row["finish"]
			end,
			["width"] = 110,
		},
	}
	return UI.Screen "Screen" {
		gap = "m",
		UI.ScrollView "Content" {
			gap = "m",
			height = "fill" :: "fill",
			padding = { ["bottom"] = 24, ["left"] = 20, ["right"] = 20, ["top"] = 20 },
			width = "fill" :: "fill",
			UI.Text "Eyebrow" {
				role = "secondary" :: "secondary",
				text = "FACET HOME",
				textRole = "caption" :: "caption",
				wrap = true,
			},
			UI.Text "Heading" {
				text = "A room that feels like you.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary" :: "secondary",
				text = "Choose a piece. Find its place. Make it yours.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "Selection" {
				text = "Selected: Cloud sofa · Place 1",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.TextInput "FurnitureSearch" {
				clearButton = true,
				placeholder = "Find furniture",
				value = state_n7,
			},
			UI.Text "InventoryHeading" {
				text = "YOUR INVENTORY",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "InventoryHelp" {
				text = "Select to choose. Swipe or right-click for actions.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Table "FurnitureInventory" {
				Size = UDim2.new(1, 0, 0, 340),
				columns = columns_n10,
				from = if data and data["InventoryRows"]
					then data["InventoryRows"]
					else {
						[1] = {
							["category"] = "Comfort",
							["finish"] = "Sage",
							["id"] = "sofa",
							["name"] = "Leather loveseat",
							["quantity"] = 0,
						},
						[2] = {
							["category"] = "Living",
							["finish"] = "Sage",
							["id"] = "table",
							["name"] = "Oak table",
							["quantity"] = 0,
						},
						[3] = {
							["category"] = "Lighting",
							["finish"] = "Sage",
							["id"] = "lamp",
							["name"] = "Reading lamp",
							["quantity"] = 0,
						},
						[4] = {
							["category"] = "Greenery",
							["finish"] = "Sage",
							["id"] = "plant",
							["name"] = "Monstera",
							["quantity"] = 0,
						},
						[5] = {
							["category"] = "Living",
							["finish"] = "Sage",
							["id"] = "shelf",
							["name"] = "Story shelf",
							["quantity"] = 0,
						},
						[6] = {
							["category"] = "Comfort",
							["finish"] = "Sage",
							["id"] = "rug",
							["name"] = "Sunrise rug",
							["quantity"] = 0,
						},
					},
				itemSize = 76,
				key = "id",
				onActivate = function(item: any, key: any, input: any, clickCount: any)
					if data and data["ChooseFurniture"] then
						data["ChooseFurniture"](item, key, input, clickCount)
					end
				end,
				rowActions = function(current: any): Facet.RowActionsOptions
					return {
						trailing = {
							[1] = {
								["id"] = "choose",
								["label"] = "Choose",
								["onActivate"] = function()
									if data and data["ChooseFurniture"] then
										data["ChooseFurniture"](current:peek())
									end
								end,
							},
							[2] = {
								["id"] = "place",
								["label"] = "Place here",
								["onActivate"] = function()
									if data and data["PlaceFurniture"] then
										data["PlaceFurniture"](current:peek())
									end
								end,
							},
						},
						fullSwipe = false,
					}
				end,
			},
			UI.Text "EmptyFurniture" {
				text = "No furniture matches. Clear your search.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "RoomPlanHeading" {
				text = "ROOM PLAN · Pick a place",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Grid "RoomPlan" {
				cellHeight = 56,
				columns = 3,
				gap = "s",
				UI.Button "Slot_1" {
					appearance = "standard" :: "standard",
					label = "Place 1",
				},
				UI.Button "Slot_2" {
					appearance = "standard" :: "standard",
					label = "Place 2",
				},
				UI.Button "Slot_3" {
					appearance = "standard" :: "standard",
					label = "Place 3",
				},
				UI.Button "Slot_4" {
					appearance = "standard" :: "standard",
					label = "Place 4",
				},
				UI.Button "Slot_5" {
					appearance = "standard" :: "standard",
					label = "Place 5",
				},
				UI.Button "Slot_6" {
					appearance = "standard" :: "standard",
					label = "Place 6",
				},
			},
			UI.Button "Place" {
				appearance = "emphasis" :: "emphasis",
				label = "Place selected furniture",
			},
			UI.Grid "EditActions" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Rotate" {
					appearance = "standard" :: "standard",
					label = "Rotate",
				},
				UI.Button "Remove" {
					appearance = "standard" :: "standard",
					label = "Remove",
				},
			},
			UI.Text "ColorHeading" {
				text = "FINISH · Choose a palette",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Grid "Palettes" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Palette_sage" {
					appearance = "standard" :: "standard",
					label = "Sage",
				},
				UI.Button "Palette_clay" {
					appearance = "standard" :: "standard",
					label = "Clay",
				},
				UI.Button "Palette_cream" {
					appearance = "standard" :: "standard",
					label = "Cream",
				},
				UI.Button "Palette_midnight" {
					appearance = "standard" :: "standard",
					label = "Midnight",
				},
			},
			UI.Grid "SaveActions" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Save" {
					appearance = "emphasis" :: "emphasis",
					label = "Save room",
				},
				UI.Button "Restore" {
					appearance = "standard" :: "standard",
					label = "Restore saved room",
				},
			},
		},
	}
end
