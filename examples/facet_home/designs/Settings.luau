--!strict

local Facet = require(game:GetService("ReplicatedStorage").Facet)

export type Props = {}

local _design = { contract = { inputs = {}, outputs = {} }, name = "Settings" }

local function Settings(UI: Facet.Controls, props: Props): GuiObject
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
				text = "Make yourself comfortable.",
				textRole = "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary",
				text = "Presentation settings stay available while you build and play.",
				textRole = "body",
				wrap = true,
			},
			UI.Button "TogglePalette" {
				appearance = "standard",
				label = "Switch light / dark",
			},
			UI.Button "ToggleText" {
				appearance = "standard",
				label = "Switch regular / larger text",
			},
			UI.Button "ToggleMode" {
				appearance = "standard",
				label = "Switch flat / immersive view",
			},
			UI.Text "Access" {
				text = "Flat mode keeps every room action available. World prompts support keyboard, touch, and controller. Motion follows your device preference.",
				textRole = "body",
				wrap = true,
			},
		},
	}
end

return Settings
