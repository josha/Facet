--!strict

local function initialMembers()
	return {
		{ id = "ada", name = "Ada Quill", image = "rbxassetid://75342910516929", presence = "online" },
		{ id = "bo", name = "Bo Lane", image = "rbxassetid://75342910516929", presence = "away" },
		{ id = "noel", name = "Émile Noël", presence = "busy" },
		{ id = "cote", name = "Côte 東京", presence = "offline" },
		{ id = "kai", name = "Kai North" },
		{ id = "ivy", name = "Ivy Moss" },
	}
end
return {
	title = "Player groups",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local items, variant = Compose.cell(initialMembers()), Compose.cell("stacked")
		local size, activations = Compose.cell("regular"), Compose.cell(0)
		local record
		local function report()
			return {
				count = #items:peek(),
				hidden = math.max(0, #items:peek() - 4),
				variant = variant:peek(),
				controlSize = size:peek(),
				activations = activations:peek(),
			}
		end
		local function reorder()
			local nextItems = table.clone(items:peek())
			local first = table.remove(nextItems, 1)
			table.insert(nextItems, first)
			items:set(nextItems)
			return report()
		end
		local function fewer()
			local nextItems = table.clone(items:peek())
			if #nextItems > 1 then
				table.remove(nextItems)
			end
			items:set(nextItems)
			return report()
		end
		local function restore()
			items:set(initialMembers())
			return report()
		end
		local function setVariant(value)
			variant:set(value)
			return report()
		end
		local function setSize(value)
			size:set(value)
			return report()
		end
		local function source()
			local nextItems = table.clone(items:peek())
			for index, member in nextItems do
				if member.id == "ada" then
					local changed = table.clone(member)
					changed.image = if member.image == "rbxassetid://75342910516929"
						then "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150"
						else "rbxassetid://75342910516929"
					nextItems[index] = changed
				end
			end
			items:set(nextItems)
			return report()
		end
		local function section()
			local root = Host.Frame({
				Name = "GroupRecipe",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Label({

					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Players together",
					TextSize = 22,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					Name = "Note",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Faces keep their identity when reordered. Choose the group using the count.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Compose.OrderedCollection({
					from = function(use)
						return { use(variant) }
					end,
					key = function(value)
						return value
					end,
					render = function(current, placement, key)
						local value = current:peek()
						return UI.AvatarGroup({
							Name = "Team",
							items = items,
							controlSize = size,
							layout = if value == "spread" then "spread" else "stacked",
							overflow = if value == "ellipsis" then "ellipsis" else "count",
							onOverflow = function()
								activations:set(activations:peek() + 1)
							end,
							ref = function(value)
								record = value
							end,
						})
					end,
				}),
				Host.Frame({

					Name = "RosterActions",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Reorder",
						label = "Reorder",
						onActivate = reorder,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Fewer",
						label = "Fewer",
						onActivate = fewer,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Restore",
						label = "Restore",
						onActivate = restore,
					}),
					UI.Button({
						LayoutOrder = 4,
						Name = "ChangePicture",
						label = "Change picture",
						onActivate = source,
					}),
				}),
				Host.Frame({

					Name = "LayoutActions",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Stacked",
						label = "Stacked",
						onActivate = function()
							setVariant("stacked")
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Spread",
						label = "Spread",
						onActivate = function()
							setVariant("spread")
						end,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Ellipsis",
						label = "Ellipsis",
						onActivate = function()
							setVariant("ellipsis")
						end,
					}),
					UI.Button({
						LayoutOrder = 4,
						Name = "Compact",
						label = "Compact",
						onActivate = function()
							setSize("compact")
						end,
					}),
					UI.Button({
						LayoutOrder = 5,
						Name = "Large",
						label = "Large",
						onActivate = function()
							setSize("large")
						end,
					}),
				}),
				UI.Label({

					Name = "Activations",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = function(use)
						return `Selected the group {use(activations)} times`
					end,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
			return root
		end
		return {
			section = section,
			screen = function()
				return Host.Frame({
					Name = "AvatarGroup",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame({
						Name = "Content",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						section(),
					}),
				})
			end,
			report = report,
			steps = {
				reorder = reorder,
				fewer = fewer,
				restore = restore,
				source = source,
				stacked = function()
					return setVariant("stacked")
				end,
				spread = function()
					return setVariant("spread")
				end,
				ellipsis = function()
					return setVariant("ellipsis")
				end,
				compact = function()
					return setSize("compact")
				end,
				large = function()
					return setSize("large")
				end,
			},
			reset = function()
				items:set(initialMembers())
				variant:set("stacked")
				size:set("regular")
				activations:set(0)
			end,
		}
	end,
}
