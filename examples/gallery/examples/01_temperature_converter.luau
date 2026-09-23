--!strict

local example = { title = "Temperature Converter" }
local function acceptNumeric(proposed: string): string?
	return if string.match(proposed, "^%-?%d*%.?%d*$") then proposed else nil
end
local function toCelsius(text: string): number?
	local n = tonumber(text)
	return if n then (n - 32) * 5 / 9 else nil
end
function example.build(ctx: any)
	local UI, Compose = ctx.UI, ctx.Compose
	local Host = ctx.Host
	local Compose = ctx.Compose
	local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
	local UDim, UDim2, Vector2, Color3, Enum =
		nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
	local fahrenheit = Compose.cell("")
	local celsius = Compose.cell(nil :: number?)

	local liveCelsius = Compose.formula(function(use)
		return toCelsius(use(fahrenheit))
	end)
	local function clear()
		ctx.runtime:batch(function()
			fahrenheit:set("")
			celsius:set(nil)
		end)
	end
	local built: any = { clearPath = "/TempConverter/Page/Clear", dispose = function() end, clear = clear }
	function built.fahrenheitText()
		return fahrenheit:peek()
	end
	function built.liveCelsius()
		return liveCelsius:peek()
	end
	function built.celsius()
		return celsius:peek()
	end
	function built.screen()
		return Host.Frame({
			Name = "TempConverter",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Host.UIPadding({
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			Host.ScrollingFrame({
				Name = "Page",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Fahrenheit → Celsius",
					TextSize = 28,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Prompt",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Enter a temperature in °F:",
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput({
					LayoutOrder = 3,
					Name = "Fahrenheit",
					value = fahrenheit,
					placeholder = "e.g. 212",
					validate = acceptNumeric,
					onCommit = function(text)
						celsius:set(toCelsius(text))
					end,
				}),
				UI.Label({
					LayoutOrder = 4,
					Name = "Preview",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextSize = 16,
					Text = function(use)
						local c = use(liveCelsius)
						return if c == nil
							then "Preview: —"
							else string.format("Preview: %g °C  (live, as you type)", c)
					end,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 5,
					Name = "Result",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextSize = 22,
					Text = function(use)
						local c = use(celsius)
						return if c == nil then "Result: —" else string.format("Result: %g °C", c)
					end,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Button({ LayoutOrder = 6, Name = "Clear", label = "Clear", onActivate = clear }),
			}),
		})
	end
	return built
end
return example
