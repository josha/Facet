--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose

export type Row = { [string]: unknown }
export type Data = {}

return function(UI: Facet.Controls, data: Data?): GuiObject
	return UI.Screen "Screen" {
		gap = "m",
		UI.ScrollView "Content" {
			gap = "m",
			height = "fill",
			padding = { ["bottom"] = 24, ["left"] = 20, ["right"] = 20, ["top"] = 20 },
			width = "fill",
			UI.Text "Eyebrow" {
				role = "secondary",
				text = "FACET HOME",
				textRole = "caption",
				wrap = true,
			},
			UI.Text "Heading" {
				text = "Welcome home.",
				textRole = "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary",
				text = "Create a space that feels like you.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "WallSummary" {
				text = "Six places for your favorite things.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "WallTip" {
				text = "Use Home for all actions, or follow the room markers.",
				textRole = "body",
				wrap = true,
			},
		},
	}
end
