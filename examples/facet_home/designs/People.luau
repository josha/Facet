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
				text = "Better with company.",
				textRole = "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary",
				text = "These are the people in this server. Everyone has their own room. Walk the neighborhood together.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "Presence" {
				text = "Just you here for now.",
				textRole = "body",
				wrap = true,
			},
			UI.Button "ExploreNeighborhood" {
				appearance = "emphasis",
				label = "Explore the neighborhood",
			},
		},
	}
end
