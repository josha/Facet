--!strict

local Facet = require(game:GetService("ReplicatedStorage").Facet)

export type Props = {}

local _design = { contract = { inputs = {}, outputs = {} }, name = "Activities" }

local function Activities(UI: Facet.Controls, props: Props): GuiObject
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
				text = "A moment of play.",
				textRole = "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary",
				text = "Follow the four notes: LEAF → SUN → WATER → BLOOM. A wrong note starts the sequence again.",
				textRole = "body",
				wrap = true,
			},
			UI.Text "ActivityProgress" {
				text = "0 / 4 notes",
				textRole = "body",
				wrap = true,
			},
			UI.Text "ActivityResult" {
				text = "Start with LEAF.",
				textRole = "body",
				wrap = true,
			},
			UI.Grid "Notes" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Note_1" {
					appearance = "standard",
					label = "WATER",
				},
				UI.Button "Note_2" {
					appearance = "standard",
					label = "LEAF",
				},
				UI.Button "Note_3" {
					appearance = "standard",
					label = "BLOOM",
				},
				UI.Button "Note_4" {
					appearance = "standard",
					label = "SUN",
				},
			},
			UI.Button "ResetActivity" {
				appearance = "standard",
				label = "Play again",
			},
			UI.Button "Garden" {
				appearance = "soft",
				label = "Visit the garden",
			},
		},
	}
end

return Activities
