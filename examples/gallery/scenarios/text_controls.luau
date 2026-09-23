--!strict
return {
	title = "Writing and search",
	ledgerRows = { "CONTROL-TEXT" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local text = Compose.cell("Write your race notes here.")
		local query = Compose.cell("")
		local draft = Compose.cell("3")
		local laps = Compose.cell(3)
		local enabled = Compose.cell(true)
		local saved = Compose.cell("No notes saved yet.")
		local matches = Compose.formula(function(use)
			local out = {}
			for _, name in
				{ "Coastal circuit", "Forest sprint", "Harbor loop", "Mountain pass", "Night rally", "Riverside run" }
			do
				if string.find(string.lower(name), string.lower(use(query)), 1, true) then
					table.insert(out, name)
				end
			end
			return if #out == 0 then { "No matching tracks." } else out
		end)
		local function reset()
			text:set("Write your race notes here.")
			query:set("")
			draft:set("3")
			laps:set(3)
			enabled:set(true)
			saved:set("No notes saved yet.")
		end
		local function body()
			return Host.Frame({
				Name = "Body",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Writing and search",
					TextSize = 28,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Button({

					Name = "Enable",
					label = function(use)
						return if use(enabled) then "Disable fields" else "Enable fields"
					end,
					onActivate = function()
						enabled:set(not enabled:peek())
					end,
				}),
				UI.Button({ Name = "Reset", label = "Reset", onActivate = reset }),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Race notes",
					TextSize = 22,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Enter starts a new line. Save notes commits your text.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput({

					Name = "Editor",
					value = text,
					multiline = true,
					enabled = enabled,
					onCommit = function(v)
						saved:set(v)
					end,
				}),
				UI.Button({

					Name = "Save",
					label = "Save notes",
					enabled = enabled,
					onActivate = function()
						saved:set(text:peek())
					end,
				}),
				UI.Label({

					Name = "Saved",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = saved,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Find a track",
					TextSize = 22,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput({

					Name = "Search",
					value = query,
					presentation = "search",
					enabled = enabled,
				}),
				Compose.OrderedCollection({
					from = matches,
					key = function(name)
						return name
					end,
					render = function(name)
						return UI.Label({
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Text = function(use)
								return use(name)
							end,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						})
					end,
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Lap count · 1 to 99",
					TextSize = 22,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput({

					Name = "Laps",
					value = draft,
					presentation = "number",
					numericValue = laps,
					min = 1,
					max = 99,
					enabled = enabled,
				}),
				UI.Label({

					Name = "Committed",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = function(use)
						return "Committed laps: " .. tostring(use(laps))
					end,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
		end
		return {
			screen = function()
				return Host.Frame({
					Name = "TextControls",
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
						body(),
					}),
				})
			end,

			steps = {
				disable = function()
					enabled:set(false)
				end,
				enable = function()
					enabled:set(true)
				end,
				no_results = function()
					query:set("no such track")
				end,
			},
			report = function()
				return {
					text = text:peek(),
					query = query:peek(),
					laps = laps:peek(),
					enabled = enabled:peek(),
					editor = text:peek(),
					number = draft:peek(),
					saved = saved:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
