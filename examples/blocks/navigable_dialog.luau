--!strict
local Facet = require(game:GetService("ReplicatedStorage").Facet)
local NavigableDialog = require(game:GetService("ReplicatedStorage").FacetDialogDesign)

return function(UI: Facet.Controls): Instance
	local open = Facet.Compose.cell(false)
	local path = Facet.Compose.cell<<Facet.NavigationPath>>({})
	local music = Facet.Compose.cell(true)
	local volume = Facet.Compose.cell(50)
	return UI.Screen "DialogSample" {
		UI.Button "OpenPreferences" {
			label = "Preferences",
			onActivate = function()
				open:set(true)
			end,
		},
		NavigableDialog(UI, {
			open = open,
			path = path,
			music = music,
			volume = volume,
			onPresentedChange = function(value: boolean)
				open:set(value)
			end,
			onDetails = function()
				path:set({ { id = "details" } })
			end,
		}),
	}
end
