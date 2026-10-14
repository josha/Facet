--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose

return function(UI: Facet.Controls, data: { [string]: any }?): GuiObject
	return UI.Screen {
		Name = "Screen",
		gap = "m",
		UI.ScrollView {
			Name = "Content",
			gap = "m",
			height = "fill" :: "fill",
			padding = { ["bottom"] = 24, ["left"] = 20, ["right"] = 20, ["top"] = 20 },
			width = "fill" :: "fill",
			UI.Text {
				Name = "Eyebrow",
				role = "secondary" :: "secondary",
				text = "FACET HOME",
				textRole = "caption" :: "caption",
				wrap = true,
			},
			UI.Text {
				Name = "Heading",
				text = "Welcome home.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text {
				Name = "Subtitle",
				role = "secondary" :: "secondary",
				text = "Create a space that feels like you.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text {
				Name = "WallSummary",
				text = "Six places for your favorite things.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text {
				Name = "WallTip",
				text = "Use Home for all actions, or follow the room markers.",
				textRole = "body" :: "body",
				wrap = true,
			},
		},
	}
end
