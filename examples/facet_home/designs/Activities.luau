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
				text = "A moment of play.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text "Subtitle" {
				role = "secondary" :: "secondary",
				text = "Follow the four notes: LEAF → SUN → WATER → BLOOM. A wrong note starts the sequence again.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "ActivityProgress" {
				text = "0 / 4 notes",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text "ActivityResult" {
				text = "Start with LEAF.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Grid "Notes" {
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button "Note_1" {
					appearance = "standard" :: "standard",
					label = "WATER",
				},
				UI.Button "Note_2" {
					appearance = "standard" :: "standard",
					label = "LEAF",
				},
				UI.Button "Note_3" {
					appearance = "standard" :: "standard",
					label = "BLOOM",
				},
				UI.Button "Note_4" {
					appearance = "standard" :: "standard",
					label = "SUN",
				},
			},
			UI.Button "ResetActivity" {
				appearance = "standard" :: "standard",
				label = "Play again",
			},
			UI.Button "Garden" {
				appearance = "soft" :: "soft",
				label = "Visit the garden",
			},
		},
	}
end
