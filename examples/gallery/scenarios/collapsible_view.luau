--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)
local COPY = {
	title = "Collapsible views",
	intro = "Open a custom settings view, or expand the selected destination below.",
	settings = "Race settings",
	coast = "Coast",
	forest = "Forest",
	summit = "Summit",
}
return {
	title = "Collapsible views",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local expanded = Compose.cell(false)
		local club = Compose.cell(false)
		local selected = Compose.cell("coast")
		local label = Compose.formula(function(use: Use)
			return if use(club) then "Club race settings" else copy.settings
		end)
		local icon = Compose.formula(function(use: Use)
			return if use(club) then "check" else "flag"
		end)
		local function settingsContent(): Instance
			return Host.Frame "SettingsContent" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}) :: unknown,
				UI.Text({
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = copy.settings,
					textRole = "heading" :: "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Toggle({
					LayoutOrder = 2,
					Name = "Club",
					label = "Club membership",
					value = club,
				}),
				UI.Text({
					LayoutOrder = 3,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "The button summary and image follow the choice in this view.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}
		end
		local tabs = {}
		for _, key in { "coast", "forest", "summit" } do
			table.insert(tabs, {
				id = key,
				label = copy[key],
				icon = "flag",
				content = function(): Instance
					return Host.ScrollingFrame "Course" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 16),
						}) :: unknown,
						UI.Text({
							LayoutOrder = 1,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = copy[key],
							textRole = "title" :: "title",
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
							text = "Expand the navigation button to choose a different destination. Back returns focus to the button.",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Button({
							LayoutOrder = 3,
							Name = "Practice",
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							label = "Practice this course",
							onActivate = function() end,
						}),
					}
				end,
			})
		end
		local function Example()
			return Host.Frame "CollapsibleView" {
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
						textRole = "title" :: "title",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}) :: unknown,
					UI.Text({
						LayoutOrder = 2,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = copy.intro,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.CollapsibleView({
						LayoutOrder = 3,
						Name = "Settings",
						label = label,
						icon = icon,
						expanded = expanded,
						content = settingsContent,
					}),
					Host.Frame({
						LayoutOrder = 4,
						Name = "NavigationRegion",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 420),
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 0),
						}) :: unknown,
						UI.TabView({
							LayoutOrder = 1,
							Name = "Destinations",
							style = "collapsible" :: "collapsible",
							selection = selected,
							tabs = tabs,
						}),
					}),
				},
			}
		end
		return {
			screen = Example,
			steps = {
				open = function()
					expanded:set(true)
				end,
				close = function()
					expanded:set(false)
				end,
				reset = function()
					expanded:set(false)
					club:set(false)
					selected:set("coast")
				end,
			},
			states = function()
				return {
					{
						id = "settings-open",
						kind = "dialog" :: "dialog",
						open = function()
							expanded:set(true)
							return true
						end,
					},
				}
			end,
			report = function()
				return { expanded = expanded:peek(), selection = selected:peek(), club = club:peek() }
			end,
			dispose = function() end,
		}
	end,
}
