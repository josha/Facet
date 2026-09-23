--!strict
local screen = {}
function screen.build(Facet: any, runtime: any, options: any?)
	local Compose = Facet.Compose
	local types = options and options.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
	local Host = runtime.constructors
	local UI = Facet.controls(runtime, options)
	local count = Compose.cell(0)
	local sound = Compose.cell(true)
	local visible = Compose.cell(true)
	return Host.Frame({
		Name = "Consumer",
		Size = types.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Compose.show(visible, function()
			return Host.Frame({
				Name = "Panel",
				Size = types.UDim2.new(1, -32, 0, 0),
				Position = types.UDim2.fromOffset(16, 16),
				AutomaticSize = types.Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = types.Enum.SortOrder.LayoutOrder, Padding = types.UDim.new(0, 12) }),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					Text = "Facet consumer",
					TextSize = 28,
					Size = types.UDim2.new(1, 0, 0, 36),
					BackgroundTransparency = 1,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Blurb",
					Text = "One component, local state, one theme. Press Bump and watch the count follow.",
					TextWrapped = true,
					Size = types.UDim2.new(1, 0, 0, 0),
					AutomaticSize = types.Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}),
				UI.Label({
					LayoutOrder = 3,
					Name = "Count",
					Text = function(use)
						return if use(count) == 1 then "1 tap" else `{use(count)} taps`
					end,
					Size = types.UDim2.new(1, 0, 0, 32),
					BackgroundTransparency = 1,
				}),
				UI.Toggle({ LayoutOrder = 4, Name = "Sound", label = "Sound", value = sound }),
				UI.Button({
					LayoutOrder = 5,
					Name = "Bump",
					label = "Bump",
					onActivate = function()
						count:update(function(value)
							return value + 1
						end)
					end,
				}),
				UI.Button({
					LayoutOrder = 6,
					Name = "Close",
					label = "Close",
					onActivate = function()
						visible:set(false)
					end,
				}),
			})
		end),
	})
end
return screen
