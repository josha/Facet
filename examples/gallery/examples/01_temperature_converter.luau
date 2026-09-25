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
		return UI.Screen "TempConverter" {
			UI.ScrollView "Page" {
				gap = "s",
				UI.Label "Title" { text = "Fahrenheit → Celsius", textRole = "title" },
				UI.Label "Prompt" { text = "Enter a temperature in °F:", textRole = "label", role = "secondary" },
				UI.TextInput "Fahrenheit" {
					value = fahrenheit,
					placeholder = "e.g. 212",
					validate = acceptNumeric,
					onCommit = function(text)
						celsius:set(toCelsius(text))
					end,
				},
				UI.Label "Preview" {
					role = "secondary",
					text = function(use)
						local c = use(liveCelsius)
						return if c == nil
							then "Preview: —"
							else string.format("Preview: %g °C  (live, as you type)", c)
					end,
				},
				UI.Label "Result" {
					textRole = "heading",
					text = function(use)
						local c = use(celsius)
						return if c == nil then "Result: —" else string.format("Result: %g °C", c)
					end,
				},
				UI.Button "Clear" { label = "Clear", onActivate = clear },
			},
		}
	end
	return built
end
return example
