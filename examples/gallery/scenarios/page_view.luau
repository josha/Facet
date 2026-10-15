--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
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
	build = function(ctx: ExampleContext): Built
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local ids = { "coast", "forest", "summit" }
		local selected = Compose.cell("coast")
		local picked = Compose.cell("Choose a course.")
		local function screen()
			local pages: { Tab } = {}
			for _, key in ids do
				local content: Instance = Host.Frame("Course")({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					UI.Text({
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
					Host.Frame("Preview")({
						LayoutOrder = 2,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 160),
						(function()
							local backdrop = Host.Frame("Backdrop")({ Size = UDim2.new(1, 0, 1, 0) })
							backdrop:AddTag("facet-panel")
							return backdrop
						end)(),
						(function()
							local path = Host.Path2D("Circuit")({ Thickness = 4, ZIndex = 2 })
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
					UI.Text({
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
					UI.Button "Choose" {
						LayoutOrder = 4,
						appearance = "emphasis",
						label = "Choose " .. copy[key],
						onActivate = function()
							picked:set(copy[key])
						end,
					},
				})
				table.insert(pages, {
					id = key,
					label = copy[key],
					content = content,
				})
			end
			return Host.Frame("PageView")({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Page" {
					padding = 16,
					gap = 16,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					UI.Text({
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
					UI.Text({
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
					UI.PageView "Courses" {
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						selection = selected,
						pages = pages,
					},
					UI.Text "Picked" {
						LayoutOrder = 4,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = picked,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
			})
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
