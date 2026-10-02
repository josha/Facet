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
				text = "Better with company.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary" :: "secondary",
				text = "These are the people in this server. Everyone has their own room. Walk the neighborhood together.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "Presence" {
				text = "Just you here for now.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Button "ExploreNeighborhood" {
				appearance = "emphasis" :: "emphasis",
				label = "Explore the neighborhood",
			},
		},
	}
end
