--!strict
type App = typeof(require("@repo/tools/typecheck/aliases").App)
type AppOptions = typeof(require("@repo/tools/typecheck/aliases").AppOptions)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type SheetSpec = typeof(require("@repo/tools/typecheck/aliases").SheetSpec)

local CatalogTypes = require("./catalog_types")

return function(c: CatalogTypes.Context): Instance
	local example = c.ctx
	local open = c.Compose.cell(false)
	local options: AppOptions = {
		runtime = c.app.runtime,
		types = c.types,
		name = "Facet_LabGlassSheet",
		theme = if example then example.theme else nil,
		motionLevel = if example then example.motionPreference else nil,
		sheet = { theme = if example then example.themeMode else nil },
	}
	local glass: App = c.Facet.app(options)
	c.Compose.cleanup(glass.dispose)
	local done: OverlayAction = {
		id = "Done",
		label = "Done",
		onActivate = function()
			open:set(false)
		end,
	}
	local mounted = false
	return c.UI.Button {
		Name = "OpenGlassSheet",
		label = "Show a bottom sheet at the app root",
		onActivate = function()
			if not mounted then
				mounted = true
				local _, screen = glass.mount(function()
					local spec: SheetSpec = {
						title = "Garage",
						isPresented = open,
						actions = { done },
						content = function(): Instance
							return glass.UI.Text {
								text = "The plate reaches the glass. Text, grabber and Done stay in the safe area.",
								wrap = true,
							}
						end,
					}
					return glass.UI.Sheet(spec)
				end)
				screen.DisplayOrder = 1000
			end
			open:set(true)
		end,
	}
end
