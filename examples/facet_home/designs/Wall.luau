--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose

return function(UI: Facet.Controls, data: { [string]: any }?): GuiObject
	return UI.Screen "Screen" {
		gap = "m",
		UI.ScrollView "Content" {
			gap = "m",
			height = "fill" :: "fill",
			padding = { ["bottom"] = 24, ["left"] = 20, ["right"] = 20, ["top"] = 20 },
			width = "fill" :: "fill",
			UI.Text "Eyebrow" {
				role = "secondary" :: "secondary",
				text = "FACET HOME",
				textRole = "caption" :: "caption",
				wrap = true,
			},
			UI.Text "Heading" {
				text = "Welcome home.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary" :: "secondary",
				text = "Create a space that feels like you.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "WallSummary" {
				text = "Six places for your favorite things.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "WallTip" {
				text = "Use Home for all actions, or follow the room markers.",
				textRole = "body" :: "body",
				wrap = true,
			},
		},
	}
end
