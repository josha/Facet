--!strict
type NavigationEntry = typeof(require("@repo/tools/typecheck/aliases").NavigationEntry)

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Destination = typeof(require("@repo/tools/typecheck/aliases").Destination)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)

return {
	title = "Plan a journey",
	ledgerRows = { "CAPABILITY-NAVIGATION" },
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
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
		local matches = Compose.formula(function(use: Use)
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
		local axis = Compose.formula(function(use: Use)
			local width = use(measuredWidth)
			if width <= 0 then
				width = if ctx.viewport then use(ctx.viewport).width else 920
			end
			return if width < 600 then "y" else "x"
		end)
		local function adaptColumns(frame)
			ctx.runtime.decorate(frame:FindFirstChildWhichIsA("UIListLayout"), {
				FillDirection = function(use: Use)
					return if use(axis) == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
				end,
			})
			for _, child in frame:GetChildren() do
				if child:IsA("GuiObject") then
					ctx.runtime.decorate(child, {
						Size = function(use: Use)
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
			return UI.ScrollView "Scroll" {
				padding = 16,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				ScrollBarThickness = 6,
				Host.Frame "Content" {
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundTransparency = 1,
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 8),
					}) :: unknown,
					table.unpack(content),
				},
			}
		end
		local function journey()
			return UI.NavigationStack "Journey" {
				path = path,
				backLabel = "Back",

				root = {
					title = "Plan a journey",
					content = function(): Instance
						local searchLayout = Host.Frame "SearchLayout" {
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 16),
							}) :: unknown,
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
								}) :: unknown,
								UI.Text({
									LayoutOrder = 1,
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									text = "Find a journey",
									textRole = "heading" :: "heading",
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
								UI.TextInput({
									LayoutOrder = 2,
									Name = "Search",
									value = query,
									presentation = "search" :: "search",
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
								}) :: unknown,
								UI.Text "ResultsHeading" {
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									text = function(use: Use)
										return if use(query) == "" then "Suggested journeys" else "Search results"
									end,
									textRole = "heading" :: "heading",
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								},
								Compose.OrderedCollection({
									from = function(use: Use): { { id: string, label: string } }
										return use(matches)
									end,
									key = function(item: { id: string, label: string })
										return item.id
									end,
									render = function(item: Readable<{ id: string, label: string }>): GuiObject
										local id = item:peek().id
										return UI.Button({
											Name = "Result-" .. id,
											row = {
												title = function(use: Use)
													return use(item).label
												end,
											},
											onActivate = function()
												destination:set(id)
												push({ id = "details" })
											end,
										})
									end,
								}),
								Host.Frame "Empty" {
									BackgroundTransparency = 1,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Compose.show(function(use: Use)
										return #use(matches) == 0
									end, function()
										return UI.Text({
											BackgroundTransparency = 1,
											BorderSizePixel = 0,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											text = "No journeys found. Try another name or clear search.",
											TextWrapped = true,
											TextYAlignment = Enum.TextYAlignment.Top,
											TextXAlignment = Enum.TextXAlignment.Left,
										})
									end),
								},
							}),
						}
						return page({
							UI.Text({
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								text = "Choose a destination. Your choices stay with you when you go back.",
								textRole = "caption" :: "caption",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							searchLayout,
							UI.Button "Continue" {
								label = "Plan details",
								appearance = "emphasis" :: "emphasis",
								onActivate = function()
									push({ id = "details" })
								end,
							},
						})
					end,
				},
				destinations = {
					details = {
						title = "Journey details",
						content = function(): Instance
							return page({
								Host.Frame "Columns" {
									BackgroundTransparency = 1,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									Host.UIListLayout({
										FillDirection = Enum.FillDirection.Vertical,
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 16),
									}) :: unknown,
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
										}) :: unknown,
										UI.HStack "Baseline" {
											LayoutOrder = 1,
											width = "fill" :: "fill",
											gap = "s",
											align = "end" :: "end",
											UI.Text "Label" {
												LayoutOrder = 1,
												text = "Days",
												textRole = "caption" :: "caption",
											} :: unknown,
											UI.Text "Value" {
												LayoutOrder = 2,
												text = "3",
												textRole = "title" :: "title",
											},
											UI.Spacer "FlexibleGap" { LayoutOrder = 3, minLength = minimum },
											UI.Text "Unit" {
												LayoutOrder = 4,
												text = "away",
												textRole = "body" :: "body",
											},
										},
										UI.HStack "LastBaseline" {
											LayoutOrder = 2,
											width = "fill" :: "fill",
											gap = "s",
											align = "end" :: "end",
											wrap = true,
											UI.Text {
												LayoutOrder = 1,
												text = "Travel light",
												textRole = "heading" :: "heading",
											} :: unknown,
											UI.Text {
												LayoutOrder = 2,
												text = "and enjoy the view",
												textRole = "caption" :: "caption",
											},
										},
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
										}) :: unknown,
										UI.Text({
											LayoutOrder = 1,
											BackgroundTransparency = 1,
											BorderSizePixel = 0,
											Size = UDim2.new(1, 0, 0, 0),
											AutomaticSize = Enum.AutomaticSize.Y,
											text = "Your notes",
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
								},
								UI.Button "Review" {
									label = "Review journey",
									onActivate = function()
										push({ id = "review", value = destination:peek() })
									end,
								},
							})
						end,
					} :: Destination,
					review = {
						title = "Ready to go",
						content = function(entry): Instance
							return page({
								UI.Text({
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									text = "Destination: " .. tostring((entry :: NavigationEntry).value),
									textRole = "heading" :: "heading",
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
								UI.Text({
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									text = notes,
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
								UI.Button "StartAgain" {
									label = "Back to the beginning",
									onActivate = function()
										popToRoot()
									end,
								},
							})
						end,
					} :: Destination,
				},
			}
		end
		return {
			screen = function()
				local root = Host.Frame "NavigationFlow" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 12),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}) :: unknown,
					journey(),
				}
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
						kind = "page" :: "page",
						open = function()
							path:set({ { id = "details" } })
							return true
						end,
					},
					{
						id = "review",
						kind = "page" :: "page",
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
