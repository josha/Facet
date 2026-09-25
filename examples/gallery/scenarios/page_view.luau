--!strict
local COPY = {
	title = "Pages and dots",
	intro = "Swipe one course at a time, choose any dot, or focus the dots and use Left / Right.",
	coast = "Coastal circuit",
	forest = "Forest sprint",
	summit = "Summit climb",
	coastText = "Fast harbor straights lead into a narrow old town. Keep a clean line through the final turn.",
	forestText = "Follow the river through a shaded forest. Gentle curves build toward a technical finish.",
	summitText = "Climb above the clouds, then hold your line on the way down. Each lap rewards steady braking.",
}
return {
	title = "Pages and dots",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local ids = { "coast", "forest", "summit" }
		local selected = Compose.cell("coast")
		local picked = Compose.cell("Choose a course.")
		local function screen()
			local viewport = Compose.formula(function(use)
				local v = use(ctx.viewport)
				return { w = v.width, h = v.height }
			end)
			local pages = {}
			for _, key in ids do
				table.insert(pages, {
					id = key,
					title = copy[key],
					content = Host.Frame "Course" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 16),
						}),
						UI.Label({
							LayoutOrder = 1,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = copy[key],
							textRole = "heading",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						Host.Frame({
							LayoutOrder = 2,
							Name = "Preview",
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 160),
							(function()
								local backdrop = Host.Frame "Backdrop" { Size = UDim2.new(1, 0, 1, 0) }
								backdrop:AddTag("facet-panel")
								return backdrop
							end)(),
							(function()
								local path = Host.Path2D "Circuit" { Thickness = 4, ZIndex = 2 }
								path:AddTag("facet-path")
								local points = {
									{ x = 0.15, y = 0.5 },
									{ x = 0.35, y = 0.2 },
									{ x = 0.75, y = 0.25 },
									{ x = 0.85, y = 0.65 },
									{ x = 0.4, y = 0.8 },
									{ x = 0.15, y = 0.5 },
								}
								local controls = {}
								local pointType = ctx.types.Path2DControlPoint or Path2DControlPoint
								for _, point in points do
									table.insert(controls, pointType.new(UDim2.fromScale(point.x, point.y)))
								end
								path:SetControlPoints(controls)
								return path
							end)(),
						}),
						UI.Label({
							LayoutOrder = 3,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = copy[key .. "Text"],
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Button({
							LayoutOrder = 4,
							Name = "Choose",
							appearance = "emphasis",
							label = "Choose " .. copy[key],
							onActivate = function()
								picked:set(copy[key])
							end,
						}),
					},
				})
			end
			return Host.Frame "PageView" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame "Page" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					UI.Label({
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = copy.title,
						textRole = "title",
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
						text = copy.intro,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.PageView({
						LayoutOrder = 3,
						Name = "Courses",
						Size = function(use)
							return UDim2.new(
								0,
								0,
								0,
								(function(use)
									return math.clamp(use(viewport).h * 0.75, 360, 640)
								end)(use)
							)
						end,
						AutomaticSize = Enum.AutomaticSize.X,
						selection = selected,
						pages = pages,
					}),
					UI.Label({
						LayoutOrder = 4,
						Name = "Picked",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = picked,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				},
			}
		end
		return {
			screen = screen,
			steps = {
				next = function()
					selected:set(ids[math.min(3, (table.find(ids, selected:peek()) or 1) + 1)])
				end,
				reset = function()
					selected:set("coast")
					picked:set("Choose a course.")
				end,
			},
			report = function()
				return { pager = { selection = selected:peek() }, picked = picked:peek() }
			end,
		}
	end,
}
