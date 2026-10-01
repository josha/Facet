--!strict

local chrome = {}

function chrome.canvas(Facet: any, parent: Instance): any
	local runtime = Facet.Roblox.createRuntime()
	local Host = runtime.constructors
	local stop, canvas = runtime.mount(function()
		return Host.ScrollingFrame "DesignCanvas" {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(233, 237, 245),
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.XY,
			ScrollBarThickness = 6,
			Host.UIPadding {
				PaddingTop = UDim.new(0, 24),
				PaddingLeft = UDim.new(0, 24),
				PaddingRight = UDim.new(0, 24),
				PaddingBottom = UDim.new(0, 24),
			},
		}
	end, parent)
	return {
		root = canvas,
		canvas = canvas,
		runtime = runtime,
		dispose = function()
			stop()
			runtime:dispose()
		end,
	}
end

function chrome.mount(Facet: any, parent: Instance, model: any, actions: any): any
	local runtime = Facet.Roblox.createRuntime()
	local Host = runtime.constructors
	local Compose = Facet.Compose
	local colors = {
		back = Color3.fromRGB(18, 21, 28),
		panel = Color3.fromRGB(26, 30, 40),
		button = Color3.fromRGB(37, 43, 56),
		line = Color3.fromRGB(53, 61, 78),
		text = Color3.fromRGB(232, 237, 247),
		muted = Color3.fromRGB(151, 165, 188),
		accent = Color3.fromRGB(103, 169, 255),
	}
	local canvas
	local searchInput: TextBox?
	local function corner(radius: number)
		return Host.UICorner { CornerRadius = UDim.new(0, radius) }
	end
	local function padding(amount: number)
		return Host.UIPadding {
			PaddingTop = UDim.new(0, amount),
			PaddingBottom = UDim.new(0, amount),
			PaddingLeft = UDim.new(0, amount),
			PaddingRight = UDim.new(0, amount),
		}
	end
	local function text(name: string, value: any, width: any?, height: number?, size: number?): TextLabel
		return Host.TextLabel(name) {
			Text = value,
			Size = width or UDim2.new(1, 0, 0, height or 24),
			BackgroundTransparency = 1,
			TextColor3 = colors.text,
			TextSize = size or 13,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}
	end
	local function button(name: string, label: any, callback: () -> (), width: number?): TextButton
		return Host.TextButton(name) {
			Text = label,
			Size = UDim2.fromOffset(width or 100, 30),
			BorderSizePixel = 0,
			BackgroundColor3 = colors.button,
			TextColor3 = colors.text,
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			AutoButtonColor = true,
			[Compose.event("Activated")] = callback,
			corner(6),
		}
	end
	local function row(name: string, children: { any }): Frame
		return Host.Frame(name) {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Host.UIListLayout {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			table.unpack(children),
		}
	end
	local stop, root = runtime.mount(function()
		local header = Host.Frame "Header" {
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = colors.panel,
			BorderSizePixel = 0,
			padding(14),
			text("Brand", "FACET DESIGN", UDim2.new(0, 190, 1, 0), nil, 16),
			Host.Frame "Commands" {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(354, 32),
				BackgroundTransparency = 1,
				Host.UIListLayout { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) },
				button("OpenSource", "Open source", actions.openSource, 108),
				button("Refresh", "Refresh", actions.refresh, 86),
				button("Live", function(use)
					return if use(model).live then "Live: on" else "Live: off"
				end, actions.toggleLive, 92),
				button("Reset", "Reset", actions.reset, 50),
			},
		}
		local sidebar = Host.Frame "Sidebar" {
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(0, 218, 1, -94),
			BackgroundColor3 = colors.panel,
			BorderSizePixel = 0,
			padding(12),
			Host.UIListLayout { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder },
			Host.TextBox "Search" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 34),
				Text = "",
				PlaceholderText = "Find a component…",
				BackgroundColor3 = colors.back,
				BorderSizePixel = 0,
				TextColor3 = colors.text,
				PlaceholderColor3 = colors.muted,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				ClearTextOnFocus = false,
				[Compose.event("Changed")] = function(property)
					if property == "Text" and searchInput then
						actions.search(searchInput.Text)
					end
				end,
				corner(6),
				padding(8),
			},
			text("ComponentsHeading", "COMPONENTS", nil, 22, 11),
			Host.ScrollingFrame "ComponentList" {
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0.55, -60),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 3,
				Host.UIListLayout { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder },
				Compose.keyed({
					from = function(use)
						return use(model).entries
					end,
					key = function(entry)
						return entry.module
					end,
					render = function(current)
						local entry = current:peek()
						local node = button("Component", entry.name, function()
							actions.select(entry.module)
						end, 188)
						node.Size = UDim2.new(1, -4, 0, 32)
						runtime.decorate(node, {
							BackgroundColor3 = function(use)
								return if use(model).selected == entry.module then colors.accent else colors.button
							end,
							TextColor3 = function(use)
								return if use(model).selected == entry.module then colors.back else colors.text
							end,
						})
						return node
					end,
				}),
			},
			text("StatesHeading", "SAMPLE STATES", nil, 22, 11),
			Host.ScrollingFrame "States" {
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0.45, -44),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 3,
				Host.UIListLayout { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder },
				Compose.keyed({
					from = function(use)
						return use(model).states
					end,
					key = function(value)
						return value
					end,
					render = function(current)
						local name = current:peek()
						local node = button("State", name, function()
							actions.state(name)
						end, 188)
						node.Size = UDim2.new(1, -4, 0, 32)
						runtime.decorate(node, {
							BackgroundColor3 = function(use)
								return if use(model).state == name then colors.line else colors.button
							end,
						})
						return node
					end,
				}),
			},
		}
		local controls = Host.Frame "Controls" {
			Position = UDim2.fromOffset(218, 64),
			Size = UDim2.new(1, -218, 0, 104),
			BackgroundColor3 = colors.back,
			BorderSizePixel = 0,
			padding(12),
			Host.UIListLayout { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder },
			row("DeviceControls", {
				button("Device", function(use)
					return use(model).device
				end, function()
					actions.cycle("device")
				end, 104),
				button("Rotate", "Rotate", actions.rotate, 60),
				button("Input", function(use)
					return `Input: {use(model).input}`
				end, function()
					actions.cycle("input")
				end, 136),
				button("Comparison", function(use)
					return `View: {use(model).comparison}`
				end, function()
					actions.cycle("comparison")
				end, 110),
				button("Zoom", function(use)
					return `Zoom: {use(model).zoom}`
				end, function()
					actions.cycle("zoom")
				end, 94),
			}),
			row("AppearanceControls", {
				button("Palette", function(use)
					return `Palette: {use(model).palette}`
				end, function()
					actions.cycle("palette")
				end, 124),
				button("TextSize", function(use)
					return `Text: {use(model).textSize}`
				end, function()
					actions.cycle("textSize")
				end, 114),
				button("Motion", function(use)
					return `Motion: {use(model).motionLevel}`
				end, function()
					actions.cycle("motionLevel")
				end, 116),
				button("Inspect", function(use)
					return if use(model).inspect then "Bounds: on" else "Bounds: off"
				end, actions.inspect, 90),
			}),
		}
		canvas = Host.ScrollingFrame "Canvas" {
			Position = UDim2.fromOffset(218, 168),
			Size = UDim2.new(1, -218, 1, -198),
			BackgroundColor3 = colors.back,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.XY,
			ScrollBarThickness = 6,
			ScrollingDirection = Enum.ScrollingDirection.XY,
			padding(20),
		}
		local diagnostics = Host.Frame "Diagnostics" {
			Position = UDim2.fromOffset(238, 188),
			Size = UDim2.new(1, -258, 0, 150),
			ZIndex = 2000,
			Visible = function(use)
				return use(model).error ~= ""
			end,
			BackgroundColor3 = colors.panel,
			BorderSizePixel = 0,
			corner(8),
			padding(12),
			Host.UIStroke { Color = Color3.fromRGB(226, 112, 121), Thickness = 1 },
			Host.TextBox "ErrorDetails" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				TextEditable = false,
				ClearTextOnFocus = false,
				Text = function(use)
					return use(model).error
				end,
				TextColor3 = colors.text,
				TextSize = 12,
				Font = Enum.Font.Code,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 2001,
			},
		}
		return Host.Frame "FacetDesign" {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.back,
			BorderSizePixel = 0,
			header,
			sidebar,
			controls,
			canvas,
			diagnostics,
			Host.Frame "StatusBar" {
				Position = UDim2.new(0, 0, 1, -30),
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = colors.panel,
				BorderSizePixel = 0,
				padding(6),
				text("Status", function(use)
					return use(model).status
				end, nil, 18, 11),
			},
		}
	end, parent)
	searchInput = root:FindFirstChild("Search", true)
	return {
		root = root,
		canvas = canvas,
		runtime = runtime,
		dispose = function()
			stop()
			runtime:dispose()
		end,
	}
end

return chrome
