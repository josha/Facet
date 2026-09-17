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
function example.build(Facet: any, _core: any, _deps: any)
	local UI = Facet.View
	local built: any = { clearPath = "/TempConverter/Page/Clear", dispose = function() end }
	local Converter = Facet.component(function(ui)
		local fahrenheit, setFahrenheit = ui.state("")
		local celsius, setCelsius = ui.state(nil :: number?)
		-- This derived number is shared by the preview and the driver's report.
		local liveCelsius = ui.memo(function()
			return toCelsius(fahrenheit())
		end)
		local function clear()
			ui.batch(function()
				setFahrenheit("")
				setCelsius(nil)
			end)
		end
		built.fahrenheitText, built.liveCelsius, built.celsius = fahrenheit, liveCelsius, celsius
		built.clear = clear
		return UI.Screen({
			id = "TempConverter",
			surface = "base",
			padding = "m",
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),
				UI.Text({ id = "Title", text = "Fahrenheit → Celsius", textSize = "title" }),
				UI.Text({ id = "Prompt", text = "Enter a temperature in °F:", textSize = "label", role = "secondary" }),
				UI.TextInput({
					id = "Fahrenheit",
					value = fahrenheit,
					onChange = setFahrenheit,
					placeholder = "e.g. 212",
					keyboardType = "numeric",
					validate = acceptNumeric,
					onCommit = function(text)
						setCelsius(toCelsius(text))
					end,
				}),
				UI.Text({
					id = "Preview",
					textSize = "body",
					role = "secondary",
					text = function()
						local c = liveCelsius()
						return if c == nil
							then "Preview: —"
							else string.format("Preview: %g °C  (live, as you type)", c)
					end,
				}),
				UI.Text({
					id = "Result",
					textSize = "heading",
					text = function()
						local c = celsius()
						return if c == nil then "Result: —" else string.format("Result: %g °C", c)
					end,
				}),
				UI.Button({ id = "Clear", label = "Clear", onActivate = clear }),
			}),
		})
	end)
	built.screen = Converter({})
	return built
end
return example
