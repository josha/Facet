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
				text = "A moment of play.",
				textRole = "title" :: "title",
				wrap = true,
			},
			UI.Text {
				Name = "Subtitle",
				role = "secondary" :: "secondary",
				text = "Follow the four notes: LEAF → SUN → WATER → BLOOM. A wrong note starts the sequence again.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text {
				Name = "ActivityProgress",
				text = "0 / 4 notes",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Text {
				Name = "ActivityResult",
				text = "Start with LEAF.",
				textRole = "body" :: "body",
				wrap = true,
			},
			UI.Grid {
				Name = "Notes",
				cellHeight = 56,
				columns = 2,
				gap = "s",
				UI.Button { Name = "Note_1", appearance = "standard" :: "standard", label = "WATER" },
				UI.Button { Name = "Note_2", appearance = "standard" :: "standard", label = "LEAF" },
				UI.Button { Name = "Note_3", appearance = "standard" :: "standard", label = "BLOOM" },
				UI.Button { Name = "Note_4", appearance = "standard" :: "standard", label = "SUN" },
			},
			UI.Button {
				Name = "ResetActivity",
				appearance = "standard" :: "standard",
				label = "Play again",
			},
			UI.Button { Name = "Garden", appearance = "soft" :: "soft", label = "Visit the garden" },
		},
	}
end
