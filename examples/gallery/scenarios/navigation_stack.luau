--!strict

return {
	title = "Plan a journey",
	ledgerRows = { "CAPABILITY-NAVIGATION" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local path = Compose.cell({})
		local destination = Compose.cell("coast")
		local query = Compose.cell("")
		local journeys = {
			{ id = "coast", label = "Coastal journey" },
			{ id = "forest", label = "Forest journey" },
			{ id = "mountain", label = "Mountain journey" },
		}
		local matches = Compose.formula(function(use)
			local needle = string.lower(use(query))
			local result = {}
			for _, item in journeys do
				if string.find(string.lower(item.label), needle, 1, true) then
					table.insert(result, item)
				end
			end
			return result
		end)
		local notes = Compose.cell("Meet at sunrise.")
		local minimum = Compose.cell("m")
		local alignment = Compose.cell("firstTextBaseline")
		local visits, exits = 0, 0
		local measuredWidth = Compose.cell(0)
		local axis = Compose.formula(function(use)
			local width = use(measuredWidth)
			if width <= 0 then
				width = if ctx.viewport then use(ctx.viewport).width else 920
			end
			return if width < 600 then "y" else "x"
		end)
		local function adaptColumns(frame)
			ctx.runtime.decorate(frame:FindFirstChildWhichIsA("UIListLayout"), {
				FillDirection = function(use)
					return if use(axis) == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
				end,
			})
			for _, child in frame:GetChildren() do
				if child:IsA("GuiObject") then
					ctx.runtime.decorate(child, {
						Size = function(use)
							return if use(axis) == "x" then UDim2.new(0.5, -8, 0, 0) else UDim2.new(1, 0, 0, 0)
						end,
					})
				end
			end
		end

		local function push(entry)
			local nextPath = table.clone(path:peek())
			table.insert(nextPath, entry)
			path:set(nextPath)
		end
		local function back()
			local current = path:peek()
			if #current == 0 then
				return false
			end
			local nextPath = table.clone(current)
			table.remove(nextPath)
			path:set(nextPath)
			return true
		end
		local function popToRoot()
			path:set({})
		end

		local function page(content)
			for _, child in content do
				if child.Name == "SearchLayout" or child.Name == "Columns" then
					adaptColumns(child)
				end
			end
			visits += 1
			Compose.cleanup(function()
				exits += 1
			end)
			return Host.ScrollingFrame({
				Name = "Scroll",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				Host.Frame({
					Name = "Content",
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundTransparency = 1,
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 8),
					}),
					table.unpack(content),
				}),
			})
		end
		local function journey()
			return UI.NavigationStack({
				Name = "Journey",
				path = path,
				backLabel = "Back",

				root = {
					title = "Plan a journey",
					content = function()
						local searchLayout = Host.Frame({
							Name = "SearchLayout",
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 16),
							}),
							Host.Frame({
								LayoutOrder = 1,
								Name = "SearchEntry",
								BackgroundTransparency = 1,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Host.UIListLayout({
									FillDirection = Enum.FillDirection.Vertical,
									SortOrder = Enum.SortOrder.LayoutOrder,
									Padding = UDim.new(0, 8),
								}),
								UI.Label({
									LayoutOrder = 1,
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Text = "Find a journey",
									TextSize = 22,
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
								UI.TextInput({
									LayoutOrder = 2,
									Name = "Search",
									value = query,
									presentation = "search",
									placeholder = "Search journeys",
								}),
							}),
							Host.Frame({
								LayoutOrder = 2,
								Name = "Results",
								BackgroundTransparency = 1,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Host.UIListLayout({
									FillDirection = Enum.FillDirection.Vertical,
									SortOrder = Enum.SortOrder.LayoutOrder,
									Padding = UDim.new(0, 8),
								}),
								UI.Label({

									Name = "ResultsHeading",
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Text = function(use)
										return if use(query) == "" then "Suggested journeys" else "Search results"
									end,
									TextSize = 22,
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
								Compose.OrderedCollection({
									from = matches,
									key = function(item)
										return item.id
									end,
									render = function(item)
										local id = item:peek().id
										return UI.Button({
											Name = "Result-" .. id,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											label = function(use)
												return use(item).label
											end,
											onActivate = function()
												destination:set(id)
												push({ id = "details" })
											end,
										})
									end,
								}),
								Host.Frame({

									Name = "Empty",
									BackgroundTransparency = 1,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Compose.show(function(use)
										return #use(matches) == 0
									end, function()
										return UI.Label({
											BackgroundTransparency = 1,
											BorderSizePixel = 0,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											Text = "No journeys found. Try another name or clear search.",
											TextWrapped = true,
											TextYAlignment = Enum.TextYAlignment.Top,
											TextXAlignment = Enum.TextXAlignment.Left,
										})
									end),
								}),
							}),
						})
						return page({
							UI.Label({
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Text = "Choose a destination. Your choices stay with you when you go back.",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							searchLayout,
							UI.Button({
								Name = "Continue",
								label = "Plan details",
								onActivate = function()
									push({ id = "details" })
								end,
							}),
						})
					end,
				},
				destinations = {
					details = {
						title = "Journey details",
						content = function()
							return page({
								Host.Frame({
									Name = "Columns",
									BackgroundTransparency = 1,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Host.UIListLayout({
										FillDirection = Enum.FillDirection.Vertical,
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 16),
									}),
									Host.Frame({
										LayoutOrder = 1,
										Name = "Summary",
										BackgroundTransparency = 1,
										Size = UDim2.new(1, 0, 0, 0),
										AutomaticSize = Enum.AutomaticSize.Y,
										Host.UIListLayout({
											FillDirection = Enum.FillDirection.Vertical,
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = UDim.new(0, 8),
										}),
										Host.Frame({
											LayoutOrder = 1,
											Name = "Baseline",
											BackgroundTransparency = 1,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											Host.UIListLayout({
												FillDirection = Enum.FillDirection.Horizontal,
												SortOrder = Enum.SortOrder.LayoutOrder,
												Padding = UDim.new(0, 8),
											}),
											UI.Label({
												LayoutOrder = 1,
												Name = "Label",
												BackgroundTransparency = 1,
												BorderSizePixel = 0,
												Size = UDim2.new(1, 0, 0, 0),
												AutomaticSize = Enum.AutomaticSize.Y,
												Text = "Days",
												TextSize = 12,
												TextWrapped = true,
												TextYAlignment = Enum.TextYAlignment.Top,
												TextXAlignment = Enum.TextXAlignment.Left,
											}),
											UI.Label({
												LayoutOrder = 2,
												Name = "Value",
												BackgroundTransparency = 1,
												BorderSizePixel = 0,
												Size = UDim2.new(1, 0, 0, 0),
												AutomaticSize = Enum.AutomaticSize.Y,
												Text = "3",
												TextSize = 28,
												TextWrapped = true,
												TextYAlignment = Enum.TextYAlignment.Top,
												TextXAlignment = Enum.TextXAlignment.Left,
											}),
											Host.Frame({
												LayoutOrder = 3,
												Name = "FlexibleGap",
												BackgroundTransparency = 1,
												Size = UDim2.new(0, 0, 0, 0),
												AutomaticSize = Enum.AutomaticSize.XY,
											}),
											UI.Label({
												LayoutOrder = 4,
												Name = "Unit",
												BackgroundTransparency = 1,
												BorderSizePixel = 0,
												Size = UDim2.new(1, 0, 0, 0),
												AutomaticSize = Enum.AutomaticSize.Y,
												Text = "away",
												TextSize = 16,
												TextWrapped = true,
												TextYAlignment = Enum.TextYAlignment.Top,
												TextXAlignment = Enum.TextXAlignment.Left,
											}),
										}),
										Host.Frame({
											LayoutOrder = 2,
											Name = "LastBaseline",
											BackgroundTransparency = 1,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											Host.UIListLayout({
												FillDirection = Enum.FillDirection.Horizontal,
												SortOrder = Enum.SortOrder.LayoutOrder,
												Padding = UDim.new(0, 8),
												Wraps = true,
											}),
											UI.Label({
												LayoutOrder = 1,
												BackgroundTransparency = 1,
												BorderSizePixel = 0,
												Size = UDim2.new(1, 0, 0, 0),
												AutomaticSize = Enum.AutomaticSize.Y,
												Text = "Travel light",
												TextSize = 22,
												TextWrapped = true,
												TextYAlignment = Enum.TextYAlignment.Top,
												TextXAlignment = Enum.TextXAlignment.Left,
											}),
											UI.Label({
												LayoutOrder = 2,
												BackgroundTransparency = 1,
												BorderSizePixel = 0,
												Size = UDim2.new(1, 0, 0, 0),
												AutomaticSize = Enum.AutomaticSize.Y,
												Text = "and enjoy the view",
												TextSize = 12,
												TextWrapped = true,
												TextYAlignment = Enum.TextYAlignment.Top,
												TextXAlignment = Enum.TextXAlignment.Left,
											}),
										}),
									}),
									Host.Frame({
										LayoutOrder = 2,
										Name = "Writing",
										BackgroundTransparency = 1,
										Size = UDim2.new(1, 0, 0, 0),
										AutomaticSize = Enum.AutomaticSize.Y,
										Host.UIListLayout({
											FillDirection = Enum.FillDirection.Vertical,
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = UDim.new(0, 8),
										}),
										UI.Label({
											LayoutOrder = 1,
											BackgroundTransparency = 1,
											BorderSizePixel = 0,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											Text = "Your notes",
											TextWrapped = true,
											TextYAlignment = Enum.TextYAlignment.Top,
											TextXAlignment = Enum.TextXAlignment.Left,
										}),
										UI.TextInput({
											LayoutOrder = 2,
											Name = "Notes",
											value = notes,
											multiline = true,
										}),
									}),
								}),
								UI.Button({
									Name = "Review",
									label = "Review journey",
									onActivate = function()
										push({ id = "review", value = destination:peek() })
									end,
								}),
							})
						end,
					},
					review = {
						title = "Ready to go",
						content = function(entry)
							return page({
								UI.Label({
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Text = "Destination: " .. tostring(entry.value),
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
									Text = notes,
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
								UI.Button({
									Name = "StartAgain",
									label = "Back to the beginning",
									onActivate = function()
										popToRoot()
									end,
								}),
							})
						end,
					},
				},
			})
		end
		return {
			screen = function()
				local root = Host.Frame({
					Name = "NavigationFlow",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					journey(),
				})
				local function measure()
					measuredWidth:set(root.AbsoluteSize.X)
				end
				measure()
				local connection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				return root
			end,
			steps = {
				search = function()
					query:set("forest")
				end,
				noResults = function()
					query:set("unknown")
				end,
				clearSearch = function()
					query:set("")
				end,
				push = function()
					push({ id = "details" })
				end,
				review = function()
					push({ id = "review", value = destination:peek() })
				end,
				back = function()
					return back()
				end,
				reset = function()
					popToRoot()
				end,
				spacing = function()
					minimum:set(if minimum:peek() == "m" then "xl" else "m")
				end,
				baseline = function()
					alignment:set(
						if alignment:peek() == "firstTextBaseline" then "lastTextBaseline" else "firstTextBaseline"
					)
				end,
			},
			states = function()
				return {
					{
						id = "details",
						kind = "page",
						open = function()
							path:set({ { id = "details" } })
							return true
						end,
					},
					{
						id = "review",
						kind = "page",
						open = function()
							path:set({ { id = "details" }, { id = "review", value = "coast" } })
							return true
						end,
					},
				}
			end,
			report = function()
				return {
					navigation = { depth = #path:peek() },
					visits = visits,
					exits = exits,
					notes = notes:peek(),
					destination = destination:peek(),
					query = query:peek(),
					matches = #matches:peek(),
					axis = axis:peek(),
				}
			end,
		}
	end,
}
