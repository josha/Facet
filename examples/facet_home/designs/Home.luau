--!strict

local Facet = require(game:GetService("ReplicatedStorage").Facet)

export type Props = {}

local _design = { contract = { inputs = {}, outputs = {} }, name = "Home" }

local function Home(UI: Facet.Controls, props: Props): GuiObject
	local contentPadding: Facet.Sides = { bottom = 24, left = 20, right = 20, top = 20 }
	return UI.Screen "Screen" {
		gap = "m",
		UI.ScrollView "Content" {
			gap = "m",
			height = "fill",
			padding = contentPadding,
			width = "fill",
			UI.Text "Eyebrow" {
				role = "secondary",
				text = "FACET HOME",
				textRole = "caption",
				wrap = true,
			},
			UI.Text "Heading" {
				text = "Make yourself at home.",
				textRole = "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary",
				text = "A calm place to create, play, and spend time together.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "Welcome" {
				text = "Your room is ready. Start with something that makes it yours.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "RoomSummary" {
				text = "6 places. Endless possibilities.",
				textRole = "body",
				wrap = true,
			},
			UI.Button "OpenFurnish" {
				appearance = "emphasis",
				label = "Furnish your home",
			},
			UI.Button "OpenActivities" {
				appearance = "standard",
				label = "Take a little break",
			},
			UI.Button "OpenPeople" {
				appearance = "standard",
				label = "See who is here",
			},
			UI.Button "Explore" {
				appearance = "soft",
				label = "Explore in 3D",
			},
			UI.Text "Project" {
				text = "HOME PROJECT · Arrange three pieces, then save your room.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "ProjectProgress" {
				text = "0 / 3 pieces placed",
				textRole = "body",
				wrap = true,
			},
		},
	}
end

return Home
