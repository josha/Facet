--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type StringCell = FacetTypes.Cell<string>
type Model = { objective: StringCell, trackObjective: () -> () }

return function(Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local open = Facet.Compose.cell(false)
	return UI.Screen "HUD" {
		padding = "m",
		gap = "s",
		UI.Composition "Corners" {
			UI.fill(),
			padding = "s",
			UI.Region "TasksRegion" {
				zone = "topRight",
				rank = 1,
				UI.Button "OpenTasks" {
					label = "Tasks",
					appearance = "emphasis",
					onActivate = function()
						open:set(true)
					end,
				},
			},
		},
		UI.Sheet "TasksPanel" {
			title = "Your tasks",
			isPresented = open,
			closeButton = "Close",
			content = function()
				return UI.VStack "Tasks" {
					padding = "m",
					gap = "m",
					width = "fill",
					UI.Text "Objective" { text = model.objective, textRole = "heading", wrap = true },
					UI.Text "Instructions" {
						text = "Track this task to find your next objective in the game.",
						textRole = "body",
						wrap = true,
					},
					UI.Button "Track" {
						label = "Track task",
						onActivate = function()
							model.trackObjective()
						end,
					},
				}
			end,
		},
	}
end
