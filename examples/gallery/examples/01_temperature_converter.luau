--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local example = { title = "Temperature Converter" }
local function acceptNumeric(proposed: string): string?
	return if string.match(proposed, "^%-?%d*%.?%d*$") then proposed else nil
end
local function toCelsius(text: string): number?
	local n = tonumber(text)
	return if n then (n - 32) * 5 / 9 else nil
end
function example.build(ctx: any)
	local UI, Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.UI, ctx.Compose
	local fahrenheit = Compose.cell("")
	local celsius = (function(
		value: number?
	): typeof(require("@repo/tools/typecheck/example_shapes").optionalNumber(nil :: any))
		return Compose.cell(value)
	end)(nil)

	local liveCelsius = Compose.formula(function(use: Use)
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
				UI.Text "Title" { text = "Fahrenheit → Celsius", textRole = "title" :: "title" } :: unknown,
				UI.Text "Prompt" {
					text = "Enter a temperature in °F:",
					textRole = "label" :: "label",
					role = "secondary" :: "secondary",
				},
				UI.TextInput "Fahrenheit" {
					value = fahrenheit,
					placeholder = "e.g. 212",
					validate = acceptNumeric,
					onCommit = function(text)
						celsius:set(toCelsius(text))
					end,
				},
				UI.Text "Preview" {
					role = "secondary" :: "secondary",
					text = function(use: Use)
						local c = use(liveCelsius)
						return if c == nil
							then "Preview: —"
							else string.format("Preview: %g °C  (live, as you type)", c)
					end,
				},
				UI.Text "Result" {
					textRole = "heading" :: "heading",
					text = function(use: Use)
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
