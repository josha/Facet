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
				text = "Make yourself at home.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary" :: "secondary",
				text = "A calm place to create, play, and spend time together.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "Welcome" {
				text = "Your room is ready. Start with something that makes it yours.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "RoomSummary" {
				text = "6 places. Endless possibilities.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Button "OpenFurnish" {
				appearance = "emphasis" :: "emphasis",
				label = "Furnish your home",
			},
			UI.Button "OpenActivities" {
				appearance = "standard" :: "standard",
				label = "Take a little break",
			},
			UI.Button "OpenPeople" {
				appearance = "standard" :: "standard",
				label = "See who is here",
			},
			UI.Button "Explore" {
				appearance = "soft" :: "soft",
				label = "Explore in 3D",
			},
			UI.Text "Project" {
				text = "HOME PROJECT · Arrange three pieces, then save your room.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "ProjectProgress" {
				text = "0 / 3 pieces placed",
				textRole = "body" :: "body",
				wrap = true,
			},
		},
	}
end
