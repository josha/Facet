--!strict
local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage.Facet)
local sample = require(storage.FacetDialogSample)
local runtime = Facet.Roblox.createRuntime()
runtime:watch(function()
	local viewport = Facet.Roblox.createViewport(assert(workspace.CurrentCamera))
	local base = Facet.themes.neutralPackage()
	local theme = Facet.Compose.formula(function(use: Facet.Use): Facet.ReadOnlyThemePackage
		local size = use(viewport)
		return Facet.themes.forResolution(base, size.width, size.height)
	end)
	local app = Facet.app({
		runtime = runtime,
		parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"),
		theme = theme,
	})
	Facet.Compose.cleanup(app.dispose)
	app.mount(function()
		return sample(app.UI)
	end)
end)
