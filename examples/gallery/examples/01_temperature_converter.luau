--!strict
-- Local state, property recipes, and a controlled field with live and commit edits.
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
	local fahrenheit = Compose.cell("")
	local celsius = Compose.cell(nil :: number?)
	-- This derived number is shared by the preview and the driver's report.
	local liveCelsius = Compose.formula(function(use)
		return toCelsius(use(fahrenheit))
	end)
	local function clear()
		ctx.app.runtime:batch(function()
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
		return UI.Screen("TempConverter")({
			surface = "base",
			padding = "m",
			UI.ScrollView("Page")({
				axis = "y",
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),
				UI.Text("Title")({ text = "Fahrenheit → Celsius", textSize = "title" }),
				UI.Text("Prompt")({ text = "Enter a temperature in °F:", textSize = "label", role = "secondary" }),
				UI.TextInput("Fahrenheit")({
					value = fahrenheit,
					placeholder = "e.g. 212",
					keyboardType = "numeric",
					validate = acceptNumeric,
					onCommit = function(text)
						celsius:set(toCelsius(text))
					end,
				}),
				UI.Text("Preview")({
					textSize = "body",
					role = "secondary",
					text = function(use)
						local c = use(liveCelsius)
						return if c == nil
							then "Preview: —"
							else string.format("Preview: %g °C  (live, as you type)", c)
					end,
				}),
				UI.Text("Result")({
					textSize = "heading",
					text = function(use)
						local c = use(celsius)
						return if c == nil then "Result: —" else string.format("Result: %g °C", c)
					end,
				}),
				UI.Button("Clear")({ label = "Clear", onActivate = clear }),
			}),
		})
	end
	return built
end
return example
