--!strict
local Facet = require("../../src")
local Compose = Facet.Compose
local package: Facet.ThemePackage = Facet.themes.neutralPackage()
local app: Facet.App = Facet.app({
	theme = package,
	name = "Counter",
	screen = { DisplayOrder = 10, IgnoreGuiInset = true },
	sheet = { theme = "Dark", transition = false },
})
local UI = app.UI
local function Counter(): Frame
	local count = Compose.cell(0)
	return UI.Screen({
		gap = "s",
		UI.Text({
			text = function(use: Facet.Use): string
				return `Clicked {use(count)} times`
			end,
		}),
		UI.Button({
			label = "Add one",
			onActivate = function()
				count:update(function(value: number): number
					return value + 1
				end)
			end,
		}),
	})
end
local stop: () -> (), root: ScreenGui = app.mount(Counter)
local runtime: Facet.Runtime = app.runtime
local parent: Instance = root
local other = Facet.app({ runtime = runtime, parent = parent })
other.dispose()
stop()
app.dispose()
